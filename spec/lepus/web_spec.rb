# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Web do
  describe ".assets_path" do
    it "returns a Pathname instance" do
      expect(described_class.assets_path).to be_a(Pathname)
    end

    it "returns the application root directory" do
      expected_root = Pathname.new(File.expand_path('../../web', __dir__))
      expect(described_class.assets_path).to eq(expected_root)
    end

    it "memoizes the result" do
      first_call = described_class.assets_path
      second_call = described_class.assets_path
      expect(first_call).to be(second_call)
    end
  end

  describe ".mime_for" do
    it "returns correct MIME type for HTML files" do
      expect(described_class.mime_for("index.html")).to eq("text/html")
      expect(described_class.mime_for("/path/to/file.html")).to eq("text/html")
    end

    it "returns correct MIME type for CSS files" do
      expect(described_class.mime_for("styles.css")).to eq("text/css")
      expect(described_class.mime_for("/assets/css/styles.css")).to eq("text/css")
    end

    it "returns correct MIME type for JavaScript files" do
      expect(described_class.mime_for("app.js")).to eq("application/javascript")
      expect(described_class.mime_for("/assets/js/app.js")).to eq("application/javascript")
    end

    it "returns correct MIME type for PNG images" do
      expect(described_class.mime_for("image.png")).to eq("image/png")
      expect(described_class.mime_for("/assets/images/logo.png")).to eq("image/png")
    end

    it "returns correct MIME type for JPEG images" do
      expect(described_class.mime_for("photo.jpg")).to eq("image/jpeg")
      expect(described_class.mime_for("photo.jpeg")).to eq("image/jpeg")
      expect(described_class.mime_for("/assets/images/photo.jpg")).to eq("image/jpeg")
    end

    it "returns correct MIME type for SVG images" do
      expect(described_class.mime_for("icon.svg")).to eq("image/svg+xml")
      expect(described_class.mime_for("/assets/icons/icon.svg")).to eq("image/svg+xml")
    end

    it "returns default MIME type for unknown file extensions" do
      expect(described_class.mime_for("file.txt")).to eq("application/octet-stream")
      expect(described_class.mime_for("file")).to eq("application/octet-stream")
      expect(described_class.mime_for("file.unknown")).to eq("application/octet-stream")
    end

    it "handles files without extensions" do
      expect(described_class.mime_for("README")).to eq("application/octet-stream")
    end

    it "handles empty string" do
      expect(described_class.mime_for("")).to eq("application/octet-stream")
    end
  end
end
