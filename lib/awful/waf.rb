module Awful
  module WAF

    class Base < Cli
      no_commands do
        def waf
          @_waf ||= Aws::WAF::Client.new
        end

        ## boilerplate for handling paging in all list_ methods
        def list_thing(thing)
          next_marker = nil
          things = []
          loop do
            response = waf.send("list_#{thing}", next_marker: next_marker, limit: 10)
            things += response.send(thing)
            next_marker = response.next_marker
            break unless next_marker
          end
          things
        end

        def change_token
          waf.get_change_token.change_token
        end
      end

      desc 'change [ID]', 'get or view change token'
      def change(token = nil)
        if token
          waf.get_change_token_status(change_token: token).change_token_status.output(&method(:puts))
        else
          waf.get_change_token.change_token.output(&method(:puts))
        end
      end

    end

  end
end