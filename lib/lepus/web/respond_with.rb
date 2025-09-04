# frozen_string_literal: true

module Lepus
  module Web
    class RespondWith
      TEMPLATES = {
        not_found: {
          status: 404,
          body: { error: 'not_found' }
        },
        health: {
          status: 200,
          body: { status: 'ok' }
        },
        ok: {
          status: 200,
        }
      }.freeze

      def self.json(template: nil, body: nil, status: nil, headers: {})
        headers['Content-Type'] = 'application/json'
        body ||= TEMPLATES.dig(template, :body)
        status ||= TEMPLATES.dig(template, :status) || 200
        [status, headers, [MultiJson.dump(body)]]
      end
    end
  end
end
