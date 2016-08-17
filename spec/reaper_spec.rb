require 'spec_helper'

describe Reaper do
  describe "#stop_child_process" do
    after :each do
      terminated_child_processes.clear
      reset_reaper
    end

    it "TERM's the process and then waits for it" do
      proc_double = double()
      expect(proc_double).to receive(:kill).with('TERM', 123).and_return(nil)
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect{reaper.stop_child_process('my_proc',123)}.to_not raise_error
      end
    end

    it "KILL's the process when it does not exit in time and then waits for it" do
      proc_double = double()
      expect(proc_double).to receive(:kill).with('TERM', 123).and_return(nil)
      expect(proc_double).to receive(:waitpid2).with(-1, 0) do |i,j|
        sleep 1
      end
      expect(proc_double).to receive(:kill).with('KILL', 123).and_return(nil)
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect{reaper.stop_child_process('my_proc',123, 'TERM', 0.1)}.to_not raise_error
      end
    end
  end

  describe "#waitpid_reap_other_children" do
    after :each do
      terminated_child_processes.clear
    end

    it "returns the status immediately if a process has already been waited upon succesfully" do
      terminated_child_processes[123] = "my_status"
      expect(reaper.waitpid_reap_other_children(123)).to eq("my_status")
    end

    it "calls waitpid to wait for the process to exit" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect(reaper.waitpid_reap_other_children(123)).to eq("my_status")
      end
    end

    it "returns nil when the process has no child processes" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_raise Errno::ECHILD
      mock_process(proc_double) do
        expect(reaper.waitpid_reap_other_children(123)).to eq(nil)
      end
    end

    it "stores terminated child processes while waiting" do
      proc_double = double()
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([101, "other_status"])
      expect(proc_double).to receive(:waitpid2).with(-1, 0).and_return([123, "my_status"])
      mock_process(proc_double) do
        expect(reaper.waitpid_reap_other_children(123)).to eq("my_status")
        expect(terminated_child_processes[101]).to eq("other_status")
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
