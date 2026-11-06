# frozen_string_literal: true

module Lepus
  module Web
    class App
      CONTENT_SECURITY_POLICY = [
        "default-src 'self'", "script-src 'self'", "style-src 'self'", "img-src 'self' data:",
        "font-src 'self'", "connect-src 'self'", "object-src 'none'", "base-uri 'self'",
        "form-action 'self'", "frame-ancestors 'self'"
      ].join("; ").freeze
      REVALIDATE = "no-cache"

      def self.build
        root = Web.assets_path

        Rack::Builder.new do
          use Rack::Static,
            urls: ["/assets", "/sw.js"],
            root: root.to_s,
            header_rules: [[:all, {"cache-control" => REVALIDATE}], [%w[woff2], {Rack::CONTENT_TYPE => "font/woff2"}]]

          map "/api" do
            run Lepus::Web::API.new
          end

          run ->(env) { App.index(env) }
        end
      end

      def self.index(env)
        headers = {
          "content-type" => "text/html",
          "cache-control" => REVALIDATE,
          "content-security-policy" => CONTENT_SECURITY_POLICY
        }
        [200, headers, [Web.render_index(env)]]
      end
    end
  end
end
