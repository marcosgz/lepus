# frozen_string_literal: true

require "spec_helper"
require "lepus/web"
require "rack/test"

RSpec.describe Lepus::Web::App do
  include Rack::Test::Methods

  let(:app) { described_class.build }
  let(:rand_test_dir) { ["test", SecureRandom.hex].join("/") }
  let(:assets_dir) { Lepus::Web.assets_path.join(rand_test_dir) }

  before do
    FileUtils.mkdir_p(assets_dir) unless Dir.exist?(assets_dir)
  end

  describe ".build" do
    it "returns a Rack application" do
      expect(app).to respond_to(:call)
    end

    it "builds a Rack::Builder instance" do
      expect(app).to be_a(Rack::Builder)
    end
  end

  describe "static file serving" do
    context "when requesting /" do
      it "serves the index.html file" do
        get "/"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/html")
        expect(last_response.body).to include("<!DOCTYPE html>")
      end

      it "emits a <base> tag pointing at the mount root" do
        get "/"
        expect(last_response.body).to include(%(<base href="/" />))
      end

      it "rewrites hardcoded absolute asset paths to relative ones" do
        get "/"
        expect(last_response.body).not_to match(%r{href="/assets/})
        expect(last_response.body).not_to match(%r{src="/assets/})
        expect(last_response.body).to include(%(href="assets/css/styles.css"))
      end
    end

    context "when requesting /index.html" do
      it "serves the index.html file" do
        get "/index.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/html")
        expect(last_response.body).to include("<!DOCTYPE html>")
      end
    end

    context "when requesting a CSS file" do
      it "serves CSS files with correct MIME type" do
        get "/assets/css/styles.css"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/css")
        expect(last_response.body).to include(":root")
      end
    end

    context "when requesting a JavaScript file" do
      it "serves JavaScript files with correct MIME type" do
        get "/assets/js/app.js"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/javascript")
        expect(last_response.body).to include("Stimulus.Application.start")
      end
    end

    context "when requesting a non-existent file" do
      it "falls back to serving index.html" do
        get "/non-existent-file.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/html")
        expect(last_response.body).to include("<!DOCTYPE html>")
      end
    end

    context "when requesting a file in a non-existent directory" do
      it "falls back to serving index.html" do
        get "/non-existent/directory/file.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("text/html")
        expect(last_response.body).to include("<!DOCTYPE html>")
      end
    end
  end

  describe "API routing" do
    context "when requesting /api/health" do
      it "routes to the API" do
        get "/api/health"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("application/json")
        expect(JSON.parse(last_response.body)).to eq({"status" => "ok"})
      end
    end

    context "when requesting /api/processes" do
      it "routes to the API and returns an array" do
        get "/api/processes"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("application/json")
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
      end
    end

    context "when requesting /api/queues" do
      it "routes to the API and returns an array" do
        get "/api/queues"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("application/json")
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
      end
    end

    context "when requesting /api/connections" do
      it "routes to the API and returns an array" do
        get "/api/connections"
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to eq("application/json")
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
      end
    end

    context "when requesting an unknown API endpoint" do
      it "returns 404" do
        get "/api/unknown"
        expect(last_response.status).to eq(404)
        expect(last_response.headers["content-type"]).to eq("application/json")
        expect(JSON.parse(last_response.body)).to eq({"error" => "not_found"})
      end
    end
  end

  describe "when mounted under a sub-path" do
    it "emits a <base> tag matching the mount prefix" do
      get "/", {}, "SCRIPT_NAME" => "/lepus"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include(%(<base href="/lepus/" />))
    end

    it "keeps absolute asset paths out of the rendered HTML" do
      get "/", {}, "SCRIPT_NAME" => "/lepus"
      expect(last_response.body).not_to match(%r{href="/assets/})
      expect(last_response.body).not_to match(%r{src="/assets/})
    end

    it "routes API requests through the mounted prefix" do
      get "/api/health", {}, "SCRIPT_NAME" => "/lepus"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq({"status" => "ok"})
    end
  end
end
