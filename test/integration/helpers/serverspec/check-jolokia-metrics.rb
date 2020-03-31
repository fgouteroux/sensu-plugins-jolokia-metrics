# frozen_string_literal: true

require 'spec_helper'
require 'shared_spec'
require 'yaml'

gem_path = '/usr/local/bin'
check_name = 'jolokia-metrics.rb'
check = "#{gem_path}/#{check_name}"
domain = '127.0.0.1'

describe 'ruby environment' do
  it_behaves_like 'ruby checks', check
end

describe '#get_data' do
  it 'should read YAML-formatted data from a file' do
    expected = { "data": [{ "type": 'read', "mbean": 'java.lang:type=Memory' }, { "type": 'read', "mbean": 'java.lang:type=Threading' }] }
    expect(get_data('spec/fixtures/good.yaml')).to eq expected
  end
end

describe '#get_data' do
  it 'should error out if YAML is badly formatted' do
    expect { get_data('spec/fixtures/bad.yaml') }
      .to raise_error(RuntimeError, /Error: (spec\/fixtures\/bad.yaml\/): did not find expected node content while parsing a flow node at line/)
  end
end

# connection refused
describe command("#{check} --url https://#{domain}/jolokia/read") do
  its(:exit_status) { should eq 2 }
  its(:stdout) { should match(/CheckJolokiaMetrics CRITICAL: http:\/\/127.0.0.1\/jolokia\/read is not responding/) }
end

# connection timeout
describe command("#{check} --url https://#{domain}/jolokia/read") do
  its(:exit_status) { should eq 2 }
  its(:stdout) { should match(/CheckJolokiaMetrics CRITICAL: http:\/\/127.0.0.1\/jolokia\/read Connection timed out/) }
end
