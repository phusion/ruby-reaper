#!/usr/bin/env ruby
require 'timeout'
require 'optparse'

class Reaper
  VERSION = "0.0.1"
  KILL_PROCESS_TIMEOUT = 5
  KILL_ALL_PROCESSES_TIMEOUT = 5

  LOG_LEVEL_ERROR = 1
  LOG_LEVEL_WARN  = 1
  LOG_LEVEL_INFO  = 2
  LOG_LEVEL_DEBUG = 3

  Options = Struct.new(:kill_all_on_exit, :log_level, :args)

  def initialize
    @log_level = LOG_LEVEL_DEBUG
    @terminated_child_processes = {}
  end

  def run(options)
    install_signal_handlers
    exit_code = nil
    exit_status = nil 
    args = options.args
    command = args.first
    info("Running #{args.join(' ')}...")

    pid = Process.spawn(args.join(' '))

    begin
      exit_code = waitpid_reap_other_children(pid)
      if exit_code.nil?
        info("'#{command}' exited with unknown status.")
        exit_status = 1
      else
        exit_status = exit_code.exitstatus
        info("#{command} exited with status #{exit_status}.")
      end
    rescue KeyboardInterrupt
        stop_child_process(command, pid)
        raise
    rescue
        warn("An error occurred. Aborting.")
        stop_child_process(command, pid)
        raise
    end
    exit(exit_status)
  end

  # Waits for the child process with the given PID, while at the same time
  # reaping any other child processes that have exited (e.g. adopted child
  # processes that have terminated).
  def waitpid_reap_other_children(pid)
    status = @terminated_child_processes[pid]
    if status
      # A previous call to waitpid_reap_other_children(),
      # with an argument not equal to the current argument,
      # already waited for this process. Return the status
      # that was obtained back then.
      @terminated_child_processes.delete(pid)
      return status
    end

    done = false
    status = nil
    until done
      begin
        this_pid, status = Process.waitpid2(-1, 0)
        if this_pid == pid
          done = true
        else
          # Save status for later.
          @terminated_child_processes[this_pid] = status
        end
      rescue Errno::ECHILD, Errno::ESRCH
        return nil
      end
    end
    status
  end

  def stop_child_process(name, pid, signo = 'TERM', time_limit = KILL_PROCESS_TIMEOUT)
    info("Shutting down #{name} (PID #{pid})...")
    begin
        Process.kill(signo, pid)
    rescue SystemCallError
    end

    begin
      Timeout::timeout(time_limit) do
        begin 
          waitpid_reap_other_children(pid)
        rescue SystemCallError
        end
      end
    rescue Timeout::Error
      warn("#{name} (PID #{pid}) did not shut down in time. Forcing it to exit.")
      begin
        Process.kill('KILL', pid)
      rescue SystemCallError
      end
      begin
        waitpid_reap_other_children(pid)
      rescue SystemCallError
      end
    end
  end

  def error(message)
    if @log_level >= LOG_LEVEL_ERROR
      STDERR.puts "*** #{message}"
    end
  end

  def warn(message)
    if @log_level >= LOG_LEVEL_WARN
      STDERR.puts "*** #{message}"
    end
  end

  def info(message)
    if @log_level >= LOG_LEVEL_INFO
      STDERR.puts "*** #{message}"
    end
  end

  def debug(message)
    if @log_level >= LOG_LEVEL_DEBUG
      STDERR.puts "*** #{message}"
    end
  end

  def ignore_signals_and_raise_keyboard_interrupt(signame)
    Signal.trap('TERM', 'IGNORE')
    Signal.trap('INT', 'IGNORE')
    raise KeyboardInterrupt.new(signame)
  end

  def kill_all_processes(time_limit)
    info("Killing all processes...")
    begin
      Process.kill('TERM', -1)
    rescue SystemCallError
    end

    begin
      Timeout::timeout(time_limit) do
        # Wait until no more child processes exist.
        done = false
        until done
          begin
            Process.waitpid(-1, 0)
          rescue Errno::ECHILD
            done = true
          end
        end
      end
    rescue Timeout::Error
      warn("Not all processes have exited in time. Forcing them to exit.")
      begin
        Process.kill('KILL', -1)
      rescue SystemCallError
      end
    end
  end

  def self.parse_options(args)
    reaper_opts = []
    app_opts = []
    got_split = false
    args.each do |opt|
      if opt == '--'
        got_split = true
      elsif got_split
        app_opts << opt
      else
        reaper_opts << opt
      end
    end

    options = Options.new(true, LOG_LEVEL_INFO, nil)
    parser = OptionParser.new do |parser|
      parser.banner = 'Initialize the system.'
      parser.separator ''
      parser.on('--no-kill-all-on-exit', 'Don\'t kill all processes on the system upon exiting') do
       options.kill_all_on_exit = false
      end
      parser.on('--quiet', 'Only print warnings and errors') do
        options.log_level = LOG_LEVEL_WARN
      end
    end

    parser.parse(reaper_opts)
    options.args = app_opts
    options
  end

  def install_signal_handlers
    Signal.trap 'TERM' do
      ignore_signals_and_raise_keyboard_interrupt('TERM')
    end
    Signal.trap 'INT' do
      ignore_signals_and_raise_keyboard_interrupt('INT')
    end
  end

  def self.main
    options = parse_options(ARGV)
    reaper = Reaper.new
    begin
      reaper.run(options)
    rescue KeyboardInterrupt
      reaper.warn("Init system aborted.")
      exit 2
    rescue => e
      reaper.error("Unknown error: #{e.class} #{e.message} #{e.backtrace.join("\n")}. Aborting.")
      exit 3
    ensure
      if options.kill_all_on_exit
        reaper.kill_all_processes(KILL_ALL_PROCESSES_TIMEOUT)
      end 
    end
  end

  # A SignalException that's been caught by our signal handlers
  # we can't use Interrupt because it has no constructor
  class KeyboardInterrupt < SignalException
  end
end

# Run the reaper is this file is not loaded as a library
Reaper.main if __FILE__ == $0