module Lepus
  class Supervisor < Processes::Base
    module Maintenance
      def self.included(base)
        base.send :include, InstanceMethods
      end

      module InstanceMethods
        private

        def launch_maintenance_task
          @maintenance_task = ::Concurrent::TimerTask.new(run_now: true, execution_interval: Lepus.config.process_alive_threshold) do
            prune_dead_processes
          end

          @maintenance_task.add_observer do |_, _, error|
            handle_thread_error(error) if error
          end

          @maintenance_task.execute
        end

        def stop_maintenance_task
          @maintenance_task&.shutdown
        end

        def prune_dead_processes
          wrap_in_app_executor do
            Lepus::Process.prune(excluding: process)
          end
        end
      end
    end
  end
end
