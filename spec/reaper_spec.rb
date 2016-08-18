require 'spec_helper'

describe Reaper do
  describe "#run" do
    it "stops child processes when an interrupt is triggered" do
      expect(reaper).to receive(:install_signal_handlers)
      args = ['bash', '-c', 'echo hi']
      options = Reaper::Options.new
      options.args = args
      proc_double = double()

      expect(proc_double).to receive(:spawn).with(args.join(' ')).and_return 123

      expect(reaper).to receive(:waitpid_reap_other_children)
        .with(123) do
          raise Reaper::KeyboardInterrupt.new('TERM')
      end

      expect(reaper).to receive(:stop_child_process).with('bash', 123)

      mock_process(proc_double) do
        expect{reaper.run(options)}.to raise_error(SignalException)
      end
    end

    it "runs the options.args and exits with it" do
      expect(reaper).to receive(:install_signal_handlers)
      args = ['bash', '-c', 'echo hi']
      options = Reaper::Options.new
      options.args = args
      proc_double = double()
      expect(proc_double).to receive(:spawn).with(args.join(' ')).and_return 123
      expect(reaper).to receive(:waitpid_reap_other_children)
        .with(123).and_return(double(exitstatus: 0, nil?: false))
      mock_process(proc_double) do
        expect{reaper.run(options)}.to raise_error(SystemExit)
      end
    end
  end

  describe "#kill_all_processes" do
    it "sends all children a TERM and then waits until there are no more children" do
      proc_double = double()
      expect(proc_double).to receive(:kill).with('TERM', -1).and_return(nil)
      expect(proc_double).to receive(:waitpid).with(-1, 0).and_return([123, "my_status"])
      expect(proc_double).to receive(:waitpid).with(-1, 0).and_raise(Errno::ECHILD)
      mock_process(proc_double) do
        expect{reaper.kill_all_processes(1)}.to_not raise_error
      end
    end

    it "if processes take too long it sends KILL instead" do
      proc_double = double()
      expect(proc_double).to receive(:kill).with('TERM', -1).and_return(nil)
      expect(proc_double).to receive(:waitpid).with(-1, 0) { |i,j| sleep 1}
      expect(proc_double).to receive(:kill).with('KILL', -1).and_return(nil)
      mock_process(proc_double) do
        expect{reaper.kill_all_processes(0.1)}.to_not raise_error
      end
    end
  end

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
      expect(proc_double).to receive(:waitpid2).with(-1, 0) { |i,j| sleep 1}
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

  describe "ignore_signals_and_raise_keyboard_interrupt" do
    it "traps INT and TERM and then raises a KeyboardInterrupt" do
      signal_double = double
      expect(signal_double).to receive(:trap).with('TERM', 'IGNORE')
      expect(signal_double).to receive(:trap).with('INT', 'IGNORE')
      mock_signal(signal_double) do
        expect{reaper.ignore_signals_and_raise_keyboard_interrupt('TERM')}.to raise_error(Reaper::KeyboardInterrupt)
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
