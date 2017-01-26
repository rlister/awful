require 'pp'
module Awful

  class DataPipeline < Cli

    desc 'ls [PATTERN]', 'list data pipelines'
    method_option :long, aliases: '-l', type: :boolean, default: false, desc: 'Long listing'
    def ls(name = /./)
      dps = datapipeline.list_pipelines.pipeline_id_list.select do |dp|
        dp.name.match(name)
      end

      if options[:long]
        datapipeline.describe_pipelines(pipeline_ids: dps.map(&:id)).pipeline_description_list.map do |dp|
          dp.fields.each_with_object({}) do |f, h|
            h[f.key] = f.string_value # convert array of structs to hash
          end.merge('id' => dp.pipeline_id)
        end.tap do |list|
          print_table list.map { |d| d.values_at('@creationTime', 'id', '@pipelineState', '@healthStatus', 'name') }.sort
        end
      else
        puts dps.map(&:name).sort
      end
    end

  end

end
