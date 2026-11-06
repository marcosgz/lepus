# frozen_string_literal: true

require "spec_helper"
require "lepus/web"
require "rack/test"

load File.expand_path("../../../bin/web-demo", __dir__)

RSpec.describe "bin/web-demo" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods

  let(:app) { Lepus::Web::App.build }

  [false, true].each do |heavy|
    context(heavy ? "with HEAVY=1" : "by default") do
      before do
        world = WebDemo::World.new(heavy: heavy)
        Lepus::Web.aggregator = WebDemo::Aggregator.new(world)
        Lepus::Web.management_api = WebDemo::ManagementAPI.new(world)
      end

      after do
        Lepus::Web.aggregator = nil
        Lepus::Web.management_api = nil
      end

      it "serves a consistent topology" do
        get "/api/topology"
        topology = JSON.parse(last_response.body)
        queues = topology["queues"].map { |q| q["name"] }
        exchanges = topology["exchanges"].map { |e| e["name"] }

        expect(topology["management"]).to be(true)
        expect(topology["bindings"]).not_to be_empty
        topology["bindings"].each do |binding|
          expect(exchanges).to include(binding["source"])
          expect(queues).to include(binding["destination"])
        end
        topology["queues"].reject { |q| q["role"] == "main" }.each do |queue|
          expect(queues.include?(queue["parent"]) || exchanges.include?(queue["parent_exchange"])).to be(true), queue["name"]
        end
        expect(topology["consumers"].map { |c| c["queue"] } - queues).to be_empty
      end

      it "serves processes, connections and rate history" do
        get "/api/processes"
        expect(JSON.parse(last_response.body).map { |p| p["kind"] }).to include("Supervisor", "Worker")

        get "/api/connections"
        expect(JSON.parse(last_response.body)).not_to be_empty

        get "/api/overview", age: 600
        expect(JSON.parse(last_response.body)["history"].size).to eq(60)
      end
    end
  end
end
