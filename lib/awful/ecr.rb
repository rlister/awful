require 'aws-sdk-ecr'
require 'json'
require 'base64'

module Awful
  module Short
    def ecr(*args)
      Awful::ECR.new.invoke(*args)
    end
  end

  class ECR < Cli
    no_commands do
      def ecr
        @ecr ||= Aws::ECR::Client.new
      end

      ## get array of image_tag hashes in form expected by get methods
      def image_tags(*tags)
        tags.map do |tag|
          {image_tag: tag}
        end
      end

      def describe_images(repository, tag_status = nil)
        paginate(:image_details) do |next_token|
          ecr.describe_images(
            repository_name: repository,
            filter: { tag_status: tag_status },
            next_token: next_token,
          )
        end
      end
    end

    desc 'ls', 'list commands'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls
      ecr.describe_repositories.repositories.output do |repos|
        if options[:long]
          print_table repos.map { |r| [r.repository_name, r.registry_id, r.repository_arn] }.sort
        else
          puts repos.map(&:repository_name).sort
        end
      end
    end

    desc 'dump [REPOS]', 'describe given or all repositories as yaml'
    def dump(*repos)
      repos = nil if repos.empty? # omit this arg to show all repos
      ecr.describe_repositories(repository_names: repos).repositories.output do |list|
        list.each do |repo|
          puts YAML.dump(stringify_keys(repo.to_h))
        end
      end
    end

    desc 'create REPO', 'create a repository'
    def create(repository)
      ecr.create_repository(repository_name: repository)
    end

    desc 'delete REPO', 'delete a repository'
    method_option :force, aliases: '-f', type: :boolean, default: false, desc: 'Force the deletion of the repository if it contains images'
    def delete(repository)
      if yes? "Really delete repository #{repository}?", :yellow
        ecr.delete_repository(repository_name: repository, force: options[:force])
      end
    end

    desc 'auth [REGISTRIES]', 'dump authorization details for registries (or default)'
    def auth(*registries)
      registries = nil if registries.empty?
      ecr.get_authorization_token(registry_ids: registries).authorization_data.output do |auths|
        auths.each do |auth|
          puts YAML.dump(stringify_keys(auth.to_h))
        end
      end
    end

    desc 'login [REGISTRIES]', 'run docker login for registry'
    method_option :email,                type: :string,  default: nil,    desc: 'Email for docker login command'
    method_option :print, aliases: '-p', type: :boolean, default: false,  desc: 'Print docker login command instead of running it'
    def login(*registries)
      cmd = options[:print] ? :puts : :system
      registries = nil if registries.empty?
      email = options[:email] ? "-e #{options[:email]}" : ''  # -e deprecated as of 1.14, here for older docker clients
      ecr.get_authorization_token(registry_ids: registries).authorization_data.output do |auths|
        auths.each do |auth|
          user, pass = Base64.decode64(auth.authorization_token).split(':')
          send(cmd, "docker login -u #{user} -p #{pass} #{email} #{auth.proxy_endpoint}")
        end
      end
    end

    desc 'images REPO', 'list images for repo'
    method_option :long,     aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    method_option :tagged,   aliases: '-t', type: :boolean, default: false, desc: 'show only tagged images'
    method_option :untagged, aliases: '-u', type: :boolean, default: false, desc: 'show only untagged images'
    def images(repository)
      tag_status = 'TAGGED'   if options[:tagged]
      tag_status = 'UNTAGGED' if options[:untagged]

      describe_images(repository, tag_status).output do |list|
        if options[:long]
          print_table list.map { |i|
            tags = i.image_tags || []
            size = "%.2f MiB" % (i.image_size_in_bytes/(1024*1024))
            [tags.join(','), i.image_pushed_at, size, i.image_digest]
          }
        else
          puts list.map(&:image_tags).flatten
        end
      end
    end

    desc 'get REPO TAG[S]', 'get image details for all given TAGS'
    def get(repository, *tags)
      ecr.batch_get_image(repository_name: repository, image_ids: image_tags(*tags)).images.output do |imgs|
        imgs.each do |img|
          puts YAML.dump(stringify_keys(img.to_h))
        end
      end
    end

    desc 'inspect REPO TAGS', 'get first history element from manifest'
    def inspect(repository, *tags)
      ecr.batch_get_image(repository_name: repository, image_ids: image_tags(*tags)).images.output do |imgs|
        imgs.map do |img|
          JSON.parse(JSON.parse(img.image_manifest)['history'].first['v1Compatibility'])
        end.output do |list|
          puts YAML.dump(list)
        end
      end
    end

    desc 'date REPO TAGS', 'get created date for given tags'
    def date(repository, *tags)
      ecr.batch_get_image(repository_name: repository, image_ids: image_tags(*tags)).images.output do |imgs|
        imgs.map do |img|
          parse_created(img)
        end.output do |dates|
          puts dates
        end
      end
    end

    desc 'exists REPO TAG', 'test if repo with given tag exists in registry'
    def exists(repository, tag)
      imgs = ecr.batch_get_image(repository_name: repository, image_ids: image_tags(tag)).images
      (imgs.empty? ? false : true).output(&method(:puts))
    end

    desc 'reap REPO DAYS', 'reap old images for repo'
    method_option :batch,   aliases: '-b', type: :numeric, default: 10,    desc: 'batch size to get and delete'
    method_option :dry_run, aliases: '-d', type: :boolean, default: false, desc: 'dry run, do not delete, implies verbose'
    method_option :verbose, aliases: '-v', type: :boolean, default: false, desc: 'print images to be deleted'
    def reap(repository, days, token: nil)
      verbose = options[:verbose] || options[:dry_run]
      next_token = token
      now = Time.now.utc

      deleted = failures = 0
      loop do
        response = ecr.describe_images(repository_name: repository, next_token: next_token, max_results: options[:batch])

        old_images = response.image_details.select do |image|
          date = image.image_pushed_at.utc
          age = ((now - date)/(24*60*60)).to_i
          if age > days.to_i
            puts "#{date} #{age} #{image.image_digest} #{image.image_tags}" if verbose
            true
          else
            false
          end
        end

        ## delete old images
        unless options[:dry_run] || old_images.empty?
          r = ecr.batch_delete_image(
            repository_name: repository,
            image_ids: old_images.map { |i| {image_digest: i.image_digest} }
          )
          deleted  += r.image_ids.count
          failures += r.failures.count
        end

        next_token = response.next_token
        break unless next_token
      end

      puts "deleted: #{deleted}, failures: #{failures}"
    end
  end
end
