require 'spec_helper'

describe Reaper do
  describe "constants" do
    it "has a bunch of constants" do
      expect(Reaper::KILL_PROCESS_TIMEOUT).to eq(5)
    end
  end
  describe "#parse_options" do
    it "creates an Options object" do
      opts = Reaper.parse_options("")
      expect(opts.kill_all_on_exit).to be true
      expect(opts.log_level).to eq(Reaper::LOG_LEVEL_INFO)
      expect(opts.args).to eq([''])
    end
  end
end
