# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new("test:unit") do |t|
  t.libs = ["lib", "test"]
  t.test_files = FileList["test/unit/**/*_test.rb"]
  t.warning = false
end

Rake::TestTask.new("test:integration") do |t|
  t.libs = ["lib", "test"]
  t.test_files = FileList["test/integration/**/*_test.rb"]
  t.warning = false
end

desc "Run all tests"
task test: ["test:unit", "test:integration"]

task default: :test
