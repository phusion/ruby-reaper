require 'spec_helper'

describe Reaper do
  describe "#waitpid_reap_other_children" do
    after :each do
      terminated_child_processes.clear
    end

    it "returns the status immediately if a process has already been waited upon succesfully" do
      terminated_child_processes[123] = "my_status"
      expect(Reaper.waitpid_reap_other_children(123)).to eq("my_status")
    end

    it "calls waitpid to wait for the process to exit" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect(Reaper.waitpid_reap_other_children(123)).to eq("my_status")
      end
    end

    it "returns nil when the process has no child processes" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_raise Errno::ECHILD
      mock_process(proc_double) do
        expect(Reaper.waitpid_reap_other_children(123)).to eq(nil)
      end
    end

    it "stores terminated child processes while waiting" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([101, "other_status"])
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect(Reaper.waitpid_reap_other_children(123)).to eq("my_status")
        expect(terminated_child_processes[101]).to eq("other_status")
      end
    end

    def terminated_child_processes
      Reaper.instance_variable_get(:@terminated_child_processes)
    end

    def mock_process(double)
      begin
        Reaper.const_set('Process', double)
        yield
      ensure
        Reaper.send(:remove_const, 'Process')
      end
    end
  end

  describe "#parse_options" do
    it "creates an Options object" do
      opts = Reaper.parse_options([])
      expect(opts.kill_all_on_exit).to be true
      expect(opts.log_level).to eq(Reaper::LOG_LEVEL_INFO)
      expect(opts.args).to be_empty
    end

    it "parses options" do
      opts = Reaper.parse_options(%w{--no-kill-all-on-exit --quiet -- -other-args -etc})
      expect(opts.kill_all_on_exit).to be false
      expect(opts.log_level).to eq(Reaper::LOG_LEVEL_WARN)
      expect(opts.args).to eq(['-other-args', '-etc'])
    end
  end
end
