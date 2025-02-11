# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Primitive::String do
  describe "#classify" do
    context "when dry-inflector is available" do
      before do
        stub_const("Dry::Inflector", Class.new {
                                       def classify(string)
                                         "Classified"
                                       end
                                     })
      end

      it "returns the classified string" do
        expect(described_class.new("string").classify).to eq("Classified")
      end
    end

    context "when active-support is available" do
      before do
        stub_const("ActiveSupport::Inflector", Class.new {
                                                 def self.classify(string)
                                                   "Classified"
                                                 end
                                               })
      end

      it "returns the classified string" do
        expect(described_class.new("string").classify).to eq("Classified")
      end
    end

    context "when no inflector is available" do
      it "returns the classified string" do
        expect(described_class.new("my_string").classify).to eq("MyString")
      end
    end
  end

  describe "#constantize" do
    let(:constant) { Class.new }

    before do
      stub_const("MyConstant", constant)
    end

    context "when dry-inflector is available" do
      before do
        stub_const("Dry::Inflector", Class.new {
                                       def constantize(string)
                                         MyConstant if string == "MyConstant"
                                       end
                                     })
      end

      it "returns the constantized string" do
        expect(described_class.new("MyConstant").constantize).to eq(constant)
      end
    end

    context "when active-support is available" do
      before do
        stub_const("ActiveSupport::Inflector", Class.new {
                                                 def self.constantize(string)
                                                   MyConstant if string == "MyConstant"
                                                 end
                                               })
      end

      it "returns the constantized string" do
        expect(described_class.new("MyConstant").constantize).to eq(constant)
      end
    end
  end

  describe "#underscore" do
    subject { described_class.new(arg).underscore }

    context "with capitalized string" do
      let(:arg) { "User" }

      it { is_expected.to eq("user") }
    end

    context "with camelized string" do
      let(:arg) { "UserName" }

      it { is_expected.to eq("user_name") }
    end

    context "with parameterized string" do
      let(:arg) { "foo-bar" }

      it { is_expected.to eq("foo_bar") }
    end

    context "with camelized string under a namespace" do
      let(:arg) { "Apiv2::UserName" }

      it { is_expected.to eq("apiv2/user_name") }
    end

    context "with camelized string with a root namespace" do
      let(:arg) { "::UserName" }

      it { is_expected.to eq("user_name") }
    end

    context "with a dot in the string" do
      let(:arg) { "user.name" }

      it { is_expected.to eq("user_name") }
    end

    context "with a space in the string" do
      let(:arg) { "user name" }

      it { is_expected.to eq("user_name") }
    end

    context "with multiple underscores in the string" do
      let(:arg) { "user_______name" }

      it { is_expected.to eq("user_name") }
    end
  end
end
