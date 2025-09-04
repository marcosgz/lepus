# frozen_string_literal: true

module Lepus
  module Web
    class App
      def self.build
        root = Web.assets_path

        Rack::Builder.new do
          use Rack::Static,
            urls: ["/assets", "/index.html"],
            root: root.to_s

          map "/api" do
            run Lepus::Web::API.new
          end

          run lambda { |env|
            req = Rack::Request.new(env)
            path = req.path_info
            index_path = root.join("index.html")

            if path == "/" || path == "/index.html"
              [200, {"Content-Type" => "text/html"}, [File.read(index_path)]]
            else
              # Try to serve any other static path directly; fallback to index
              file_path = root.join(path.sub(%r{^/}, ""))
              if File.file?(file_path)
                [200, {"Content-Type" => Web.mime_for(file_path)}, [File.binread(file_path)]]
              else
                [200, {"Content-Type" => "text/html"}, [File.read(index_path)]]
              end
            end
          }
        end
      end
    end
  end
end
