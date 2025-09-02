# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Processes::Callbacks do
  describe '.[]' do
    it 'creates a new instance with the given callback names' do
      callbacks = described_class[:boot, :shutdown]
      expect(callbacks).to be_a(described_class)
    end
  end

  describe '#included' do
    let(:klass) do
      Class.new do
        extend Lepus::Processes::Callbacks[:boot, :shutdown]

        def prepare
          @prepared = true
        end

        def cleanup
          @cleaned = true
        end

        def prepared?
          @prepared
        end

        def cleaned?
          @cleaned
        end
      end
    end

    it 'defines before and after callback methods for each name' do
      expect(klass).to respond_to(:before_boot, :after_boot, :before_shutdown, :after_shutdown)
    end

    it 'executes before and after callbacks in order' do
      klass.before_boot :prepare
      klass.after_shutdown :cleanup

      instance = klass.new
      result = nil

      instance.run_boot_callbacks do
        result = :booting
      end

      expect(instance.prepared?).to be true
      expect(result).to eq(:booting)

      instance.run_shutdown_callbacks do
        result = :shutting_down
      end

      expect(instance.cleaned?).to be true
      expect(result).to eq(:shutting_down)
    end

    it 'supports blocks as callbacks' do
      before_called = false
      after_called = false

      klass.before_boot { before_called = true }
      klass.after_shutdown { after_called = true }

      instance = klass.new
      instance.run_boot_callbacks {}
      instance.run_shutdown_callbacks {}

      expect(before_called).to be true
      expect(after_called).to be true
    end
  end
end
