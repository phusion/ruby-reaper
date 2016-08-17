#!/usr/bin/env ruby
require "reaper/version"
require 'timeout'
require 'optparse'

module Reaper
  KILL_PROCESS_TIMEOUT = 5
  KILL_ALL_PROCESSES_TIMEOUT = 5

  LOG_LEVEL_ERROR = 1
  LOG_LEVEL_WARN  = 1
  LOG_LEVEL_INFO  = 2
  LOG_LEVEL_DEBUG = 3

  @log_level = nil
  @terminated_child_processes = {}

  Options = Struct.new(:kill_all_on_exit, :log_level, :args)

  def run(args)
    exit_code = nil
    exit_status = nil 
    args = args.args
    info("Running #{(args).join(' ')}...")

    pid = Process.spawn(args)

    begin
      exit_code = waitpid_reap_other_children(pid)
      if exit_code.nil?
        info("#{START_COMMAND} exited with unknown status.")
        exit_status = 1
      else
        info("#{START_COMMAND} exited with status #{exit_status}.")
	exit_status = exit_code.exitstatus
      end
    rescue KeyboardInterrupt
        stop_child_process(START_COMMAND, pid)
        raise
    rescue BaseException
        warn("An error occurred. Aborting.")
        stop_child_process(START_COMMAND, pid)
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
      rescue SystemCallError => e
        case e.errno
        when Errno::ECHILD, Errno::ESRCH
          return nil
        else
          raise
        end
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
        Process.kill(pid, 'KILL')
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
    raise SignalException.new(signame)
  end

  def kill_all_processes(time_limit)
    info("Killing all processes...")
    begin
      Process.kill(-1, signal.SIGTERM)
    rescue SystemCallException
    end

    begin
      Timeout::timeout(time_limit) do
        # Wait until no more child processes exist.
        done = false
        until done
          begin
            Process.waitpid(-1, 0)
          rescue SystemCallException => e
            if e.errno == Errno::ECHILD
              done = true
            else
              raise
            end
          end
        end
      end
    rescue Timeout::Error
      warn("Not all processes have exited in time. Forcing them to exit.")
      begin
        Process.kill(-1, 'KILL')
      rescue SystemCallException
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

  def main
    options = parse_options(ARGV)
    begin
      run(args)
    rescue Interrupt
      warn("Init system aborted.")
      exit 2
    ensure
      if options.kill_all_on_exit
        kill_all_processes(KILL_ALL_PROCESSES_TIMEOUT)
      end 
    end
  end
end

