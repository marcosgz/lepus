# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::AppExecutor do
  let(:dummy_class) { Class.new { include Lepus::AppExecutor } }
  let(:instance) { dummy_class.new }

  describe '#wrap_in_app_executor' do
    let(:block) { proc { 'executed' } }

    context 'when app_executor is configured' do
      let(:app_executor) { double('AppExecutor') }

      before do
        allow(Lepus).to receive_message_chain(:config, :app_executor).and_return(app_executor)
        allow(app_executor).to receive(:wrap).and_yield
      end

      it 'wraps the block in the app executor' do
        expect(app_executor).to receive(:wrap).and_yield
        expect(instance.wrap_in_app_executor(&block)).to eq('executed')
      end
    end

    context 'when app_executor is not configured' do
      before do
        allow(Lepus).to receive_message_chain(:config, :app_executor).and_return(nil)
      end

      it 'executes the block directly' do
        expect(instance.wrap_in_app_executor(&block)).to eq('executed')
      end
    end
  end

  describe '#handle_thread_error' do
    let(:error) { StandardError.new('Test error') }

    before do
      allow(Lepus).to receive(:instrument)
    end

    context 'when on_thread_error callback is configured' do
      let(:on_thread_error) { proc { |e| e.message } }

      before do
        allow(Lepus).to receive_message_chain(:config, :on_thread_error).and_return(on_thread_error)
      end

      it 'instruments the error and calls the callback' do
        expect(Lepus).to receive(:instrument).with(:thread_error, error: error)
        expect(on_thread_error).to receive(:call).with(error)
        instance.handle_thread_error(error)
      end
    end

    context 'when on_thread_error callback is not configured' do
      before do
        allow(Lepus).to receive_message_chain(:config, :on_thread_error).and_return(nil)
      end

      it 'only instruments the error' do
        expect(Lepus).to receive(:instrument).with(:thread_error, error: error)
        instance.handle_thread_error(error)
      end
    end
  end
end
