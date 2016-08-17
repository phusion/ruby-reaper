require File.expand_path("../../lib/reaper", __FILE__)

def reaper(*args)
  if args.first
    @reaper = args.first
  else
    @reaper ||= Reaper.new()
  end
end

def reset_reaper
  @reaper = nil
end

def terminated_child_processes
  reaper.instance_variable_get(:@terminated_child_processes)
end

def mock_process(double)
  begin
    Reaper.const_set('Process', double)
    yield
  ensure
    Reaper.send(:remove_const, 'Process')
  end
end

