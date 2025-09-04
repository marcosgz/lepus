# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Web::RespondWith do
  describe ".json" do
    context "when using predefined templates" do
      it "returns not_found template response" do
        status, headers, body = described_class.json(template: :not_found)

        expect(status).to eq(404)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq({ 'error' => 'not_found' })
      end

      it "returns health template response" do
        status, headers, body = described_class.json(template: :health)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq({ 'status' => 'ok' })
      end

      it "returns ok template response with custom body" do
        custom_body = { 'data' => 'test' }
        status, headers, body = described_class.json(template: :ok, body: custom_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq({ 'data' => 'test' })
      end
    end

    context "when providing custom parameters" do
      it "returns custom status and body" do
        custom_body = { 'message' => 'Custom response' }
        status, headers, body = described_class.json(body: custom_body, status: 201)

        expect(status).to eq(201)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq({ 'message' => 'Custom response' })
      end

      it "returns custom headers" do
        custom_headers = { 'X-Custom-Header' => 'custom-value' }
        status, headers, body = described_class.json(
          template: :health,
          headers: custom_headers
        )

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(headers['X-Custom-Header']).to eq('custom-value')
        expect(JSON.parse(body.first)).to eq({ 'status' => 'ok' })
      end

      it "merges custom headers with default Content-Type" do
        custom_headers = { 'X-Custom-Header' => 'custom-value' }
        status, headers, body = described_class.json(
          template: :health,
          headers: custom_headers
        )

        expect(headers['Content-Type']).to eq('application/json')
        expect(headers['X-Custom-Header']).to eq('custom-value')
      end

      it "always sets Content-Type to application/json regardless of custom headers" do
        custom_headers = { 'Content-Type' => 'text/plain' }
        status, headers, body = described_class.json(
          template: :health,
          headers: custom_headers
        )

        expect(headers['Content-Type']).to eq('application/json')
      end
    end

    context "when providing only body without template" do
      it "returns default status 200" do
        custom_body = { 'data' => 'test' }
        status, headers, body = described_class.json(body: custom_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq({ 'data' => 'test' })
      end
    end

    context "when providing only status without template" do
      it "returns default body nil" do
        status, headers, body = described_class.json(status: 204)

        expect(status).to eq(204)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to be_nil
      end
    end

    context "when providing no parameters" do
      it "returns default response" do
        status, headers, body = described_class.json

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to be_nil
      end
    end

    context "when using unknown template" do
      it "returns default status 200 and nil body" do
        status, headers, body = described_class.json(template: :unknown)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to be_nil
      end
    end

    context "with complex data structures" do
      it "handles nested hashes" do
        complex_body = {
          'user' => {
            'id' => 1,
            'name' => 'John Doe',
            'preferences' => {
              'theme' => 'dark',
              'notifications' => true
            }
          },
          'metadata' => {
            'created_at' => '2023-01-01T00:00:00Z',
            'tags' => ['admin', 'user']
          }
        }

        status, headers, body = described_class.json(body: complex_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq(complex_body)
      end

      it "handles arrays" do
        array_body = [
          { 'id' => 1, 'name' => 'Item 1' },
          { 'id' => 2, 'name' => 'Item 2' },
          { 'id' => 3, 'name' => 'Item 3' }
        ]

        status, headers, body = described_class.json(body: array_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq(array_body)
      end

      it "handles mixed data types" do
        mixed_body = {
          'string' => 'test',
          'number' => 42,
          'boolean' => true,
          'null' => nil,
          'array' => [1, 2, 3],
          'object' => { 'nested' => 'value' }
        }

        status, headers, body = described_class.json(body: mixed_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq(mixed_body)
      end
    end

    context "with special characters and encoding" do
      it "handles unicode characters" do
        unicode_body = {
          'message' => 'Hello 世界! 🌍',
          'description' => 'Special chars: àáâãäåæçèéêë'
        }

        status, headers, body = described_class.json(body: unicode_body)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        expect(JSON.parse(body.first)).to eq(unicode_body)
      end
    end

    context "response format" do
      it "returns a proper Rack response array" do
        status, headers, body = described_class.json(template: :health)

        expect(status).to be_a(Integer)
        expect(headers).to be_a(Hash)
        expect(body).to be_an(Array)
        expect(body.length).to eq(1)
        expect(body.first).to be_a(String)
      end

      it "returns JSON string in body array" do
        custom_body = { 'test' => 'value' }
        status, headers, body = described_class.json(body: custom_body)

        expect(body.first).to be_a(String)
        expect { JSON.parse(body.first) }.not_to raise_error
        expect(JSON.parse(body.first)).to eq(custom_body)
      end
    end
  end

  describe "TEMPLATES constant" do
    it "contains expected template definitions" do
      templates = described_class::TEMPLATES

      expect(templates).to have_key(:not_found)
      expect(templates).to have_key(:health)
      expect(templates).to have_key(:ok)

      expect(templates[:not_found]).to eq({
        status: 404,
        body: { error: 'not_found' }
      })

      expect(templates[:health]).to eq({
        status: 200,
        body: { status: 'ok' }
      })

      expect(templates[:ok]).to eq({
        status: 200
      })
    end

    it "has frozen templates" do
      expect(described_class::TEMPLATES).to be_frozen
    end
  end
end
