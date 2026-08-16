# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: [:spec, :e2e]

desc "Run comprehensive end-to-end integration suite"
task :e2e do
  ruby "bin/e2e_test"
end

desc "Run performance benchmarks"
task :benchmark do
  ruby "benchmark/performance_bench.rb"
end
