#! /usr/bin/env ruby
# frozen_string_literal: false

#   jolokia-metrics.rb
#
# DESCRIPTION:
#   Read metrics from jolokia HTTP endpoint.
#
# OUTPUT:
#   Graphite formatted data
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: rest-client
#
# USAGE:
#   EX: ./jolokia-metrics.rb -u http://127.0.0.1:8080/jolokia/read -f jmx_beans.yaml
#
# LICENSE:
#   Arnaud Delalande  <arnaud.delalande@adevo.fr>
#   Francois Gouteroux <francois.gouteroux@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/metric/cli'
require 'rest-client'
require 'socket'
require 'yaml'
require 'json'
#
# Jolokia2Graphite - see description above
#
class Jolokia2Graphite < Sensu::Plugin::Metric::CLI::Graphite
  option :url,
         description: 'Full URL to the endpoint',
         short: '-u URL',
         long: '--url URL',
         default: 'http://localhost:8778/jolokia/read'

  option :scheme,
         description: 'Metric naming scheme',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: Socket.gethostname.to_s.gsub!('.', '_')

  option :file,
         description: 'File path with metrics definitions to retrieve',
         short: '-f FILE',
         long: '--file FILE'

  option :insecure,
         description: 'By default, every SSL connection made is verified to be secure. This option allows you to disable the verification',
         short: '-k',
         long: '--insecure',
         boolean: true,
         default: false

  option :debug,
         short: '-d',
         long: '--debug',
         default: false

  def deep_value(metric, input, timestamp, patterns)
    case input
    when Hash
      input.each do |key, value|
        deep_value("#{metric}.#{escape_metric(key, patterns)}", value, timestamp, patterns)
      end
    when Numeric
      output metric, input, timestamp
    end
  end

  def escape_metric(name, patterns)
    res = name.dup

    if patterns.empty?
      patterns = [
        ['*', '_'],
        ['.', '_'],
        [',', '.'],
        [' ', '_'],
        ['(', ''],
        [')', ''],
        [':', '.'],
        ['=', '.']
      ]
    end
    patterns.each { |replace| res.gsub!(replace[0], replace[1]) }
    res
  end

  def run
    puts "args config: #{config}" if config[:debug]

    begin
      cnf = YAML.load_file(config[:file])
      patterns = cnf['patterns'] || []
    rescue StandardError => e
      puts "Error: #{e.backtrace}"
      critical "Error: #{e}"
    end

    begin
      data = RestClient::Request.execute(
        url: config[:url],
        method: :post,
        payload: cnf['data'].to_json,
        headers: { content_type: 'application/json' },
        verify_ssl: !config[:insecure]
      )
      puts "Http response: #{data}" if config[:debug]

      ::JSON.parse(data).each do |resp|
        if !resp['status'] || (resp['status'] != 200)
          err = resp.to_yaml[0..300]
          if config[:debug]
            err = resp.to_yaml
          end
          warn "Error status: #{resp['status']} - Stacktrace: #{err}"
          next
        end
        mbean = resp['request']['mbean']
        attribute = resp['request']['attribute']
        path      = resp['request']['path']
        if mbean && !mbean.include?('*')
          path_ =  [mbean, attribute, path].reject { |c| !c || c.is_a?(Array) }.map { |c| escape_metric(c, patterns) }.join('.')
          metric = [config[:scheme].to_s, path_].select { |c| c }.compact.join('.')
        else
          metric = config[:scheme].to_s
        end
        deep_value(metric.to_s, resp['value'], resp['timestamp'], patterns)
      end
    rescue Errno::ECONNREFUSED
      critical "#{config[:url]} is not responding"
    rescue RestClient::RequestTimeout
      critical "#{config[:url]} Connection timed out"
    end
    ok
  end
end
