# frozen_string_literal: true

require "spec_helper"
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
        expect(last_response.headers['Content-Type']).to eq('text/html')
        expect(last_response.body).to include('<!DOCTYPE html>')
      end
    end

    context "when requesting /index.html" do
      it "serves the index.html file" do
        get "/index.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('text/html')
        expect(last_response.body).to include('<!DOCTYPE html>')
      end
    end

    context "when requesting a CSS file" do
      it "serves CSS files with correct MIME type" do
        get "/assets/css/styles.css"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('text/css')
        expect(last_response.body).to include(':root')
      end
    end

    context "when requesting a JavaScript file" do
      it "serves JavaScript files with correct MIME type" do
        get "/assets/js/app.js"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('text/javascript')
        expect(last_response.body).to include('Stimulus.Application.start')
      end
    end

    context "when requesting a non-existent file" do
      it "falls back to serving index.html" do
        get "/non-existent-file.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('text/html')
        expect(last_response.body).to include('<!DOCTYPE html>')
      end
    end

    context "when requesting a file in a non-existent directory" do
      it "falls back to serving index.html" do
        get "/non-existent/directory/file.html"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('text/html')
        expect(last_response.body).to include('<!DOCTYPE html>')
      end
    end
  end

  describe "API routing" do
    context "when requesting /api/health" do
      it "routes to the API" do
        get "/api/health"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(last_response.body)).to eq({ 'status' => 'ok' })
      end
    end

    context "when requesting /api/processes" do
      it "routes to the API" do
        get "/api/processes"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('application/json')
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
        expect(response_body.first).to include('id', 'name', 'pid', 'hostname', 'kind')
      end
    end

    context "when requesting /api/queues" do
      it "routes to the API" do
        get "/api/queues"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('application/json')
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
        expect(response_body.first).to include('name', 'type', 'messages', 'messages_ready')
      end
    end

    context "when requesting /api/connections" do
      it "routes to the API" do
        get "/api/connections"
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to eq('application/json')
        response_body = JSON.parse(last_response.body)
        expect(response_body).to be_an(Array)
        expect(response_body.first).to include('name')
      end
    end

    context "when requesting an unknown API endpoint" do
      it "returns 404" do
        get "/api/unknown"
        expect(last_response.status).to eq(404)
        expect(last_response.headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(last_response.body)).to eq({ 'error' => 'not_found' })
      end
    end
  end

  skip "MIME type handling" do
    before do
      # Create test files with different extensions in the assets directory
      # These will be served by the fallback lambda, not Rack::Static
      test_files = {
        'test.png' => 'fake png content',
        'test.jpg' => 'fake jpg content',
        'test.svg' => 'fake svg content',
        'test.txt' => 'fake txt content'
      }

      test_files.each do |filename, content|
        File.write(assets_dir.join(filename), content)
      end
    end

    after do
      test_files = ['test.png', 'test.jpg', 'test.svg', 'test.txt']
      test_files.each do |filename|
        file_path = assets_dir.join(filename)
        File.delete(file_path) if File.exist?(file_path)
      end
    end

    it "serves PNG files with correct MIME type using custom mime_for method" do
      get assets_dir.join("test.png").to_s
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to eq('image/png')
      expect(last_response.body).to eq('fake png content')
    end

    it "serves JPG files with correct MIME type using custom mime_for method" do
      get assets_dir.join("test.jpg").to_s
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to eq('image/jpeg')
      expect(last_response.body).to eq('fake jpg content')
    end

    it "serves SVG files with correct MIME type using custom mime_for method" do
      get assets_dir.join("test.svg").to_s
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to eq('image/svg+xml')
      expect(last_response.body).to eq('fake svg content')
    end

    it "serves unknown file types with default MIME type using custom mime_for method" do
      get assets_dir.join("test.txt").to_s
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to eq('application/octet-stream')
      expect(last_response.body).to eq('fake txt content')
    end
  end
end
