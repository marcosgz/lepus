# frozen_string_literal: true

module Lepus
  module Web
    class App
      def self.build
        root = Web.assets_path

        Rack::Builder.new do
          use Rack::Static,
            urls: ["/assets", "/sw.js"],
            root: root.to_s

          map "/api" do
            run Lepus::Web::API.new
          end

          run lambda { |env|
            req = Rack::Request.new(env)
            path = req.path_info

            if path == "/" || path == "/index.html"
              [200, {"content-type" => "text/html"}, [Web.render_index(env)]]
            else
              file_path = root.join(path.sub(%r{^/}, ""))
              if File.file?(file_path)
                [200, {"content-type" => Web.mime_for(file_path)}, [File.binread(file_path)]]
              else
                [200, {"content-type" => "text/html"}, [Web.render_index(env)]]
              end
            end
          }
        end
      end
    end
  end
end
