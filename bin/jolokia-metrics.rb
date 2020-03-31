#!/usr/bin/env ruby
#
#   sensu-mertic-jmx-jolokia
#
# DESCRIPTION:
#   Monitoring of JMX beans via Jolokia
#
# DEBUG:
#  search:
#     curl http://localhost:8544/jolokia/list/*:* -s |jq '.'
#  read:
#     curl 'http://localhost:8544/jolokia/read/java.lang:type=ClassLoading' -s |jq '.'
#
# LICENSE:
#   Arnaud Delalande  <arnaud.delalande@adevo.fr>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/metric/cli'
require 'json'
require 'net/http'
require 'cgi'
require 'socket'
require 'yaml'


class MerticJmxJolokia  < Sensu::Plugin::Metric::CLI::Graphite
  option :scheme,
    :description => "Metric naming scheme, text to prepend to metric",
    :short => "-s SCHEME",
    :long => "--scheme SCHEME",
    :default => "app.myapp.:::name:::.jolokia"

  option :url,
    :short => '-u URL',
    :long => '--url URL',
    :default => 'http://127.0.0.1:8544/admin',
    :description => 'The base URL to connect to (including port)'

  option :path,
    :short => '-p PATH',
    :default => 'jolokia/read',
    :description => 'The URL path to the base of Jolokia'

  option :timeout,
    :short => '-t SECS',
    :proc => proc { |a| a.to_i },
    :default => 15,
    :description => 'URL request timeout, in seconds'

  option :debug,
    :short => '-d TRUE',
    :long => '--debug TRUE',
    :default => false,
    :description => 'Debug mode'

  option :configfile,
    :short => '-c CONFIGFILE',
    :long =>  '--configfile CONFIGFILE',
    :default => false,
    :description => 'Json or Yaml file with jolokia request'

  option :all,
    :short => '-a',
    :long =>  '--all',
    :default => false,
    :description => 'show all avalible metrics, ignore all other options'

  option :credfile,
    :short => '-f',
    :long =>  '--credfile',
    :default => false,
    :description => 'yaml file with username and password'


  def run
    hostname = Socket.gethostname.gsub(".", "_")
    config[:scheme] = config[:scheme].gsub(":::name:::", hostname)

    if config[:credfile]
      credfile = YAML.load_file(config[:configfile])
      config[:user] = credfile['user']
      config[:password] = credfile['password']
    end

    #config[:user] = '<%= @mgmt_user %>'
    #config[:password] = '<%= @mgmt_passwd %>'
    
    if config[:all]
      show_all

    elsif config[:configfile]:
      conffile = YAML.load_file(config[:configfile])
      request = conffile or []

      data = post_url([config[:url], 'jolokia'].join('/'), request)
      #output data.to_yaml
      if data.is_a?(Hash) and data['status'] != 200:
        output "Error: #{data.to_yaml}"
        raise "Jolokia reports error"
      end
      data.each{ |resp|
         #output resp.to_yaml
         if !resp['status'] or  resp['status'] != 200 
             output "Error: #{resp.to_yaml}"
             next
         end
         mbean     = resp['request']['mbean']
         attribute = resp['request']['attribute']
         path      = resp['request']['path']
         if mbean and !  mbean.include? '*' 
            path_ =  [mbean, attribute, path].reject { |c| !c or c.is_a? Array   }.map{|c| escape_metric_name(c)}.join('.')
            base = ["#{config[:scheme]}", path_].reject { |c| !c }.compact.join('.')
         else
            base = "#{config[:scheme]}"
         end
         deep_output("#{base}", resp['value'], resp['timestamp'] )
      }
    end
    ok
  end

  def show_all()
   # List all beans and show one by one 
   res = post_url([config[:url], 'jolokia'].join('/'), {'type' => 'list'})
    #output res.to_yaml
    if res['status'] != 200:
      output "Error while listing, #{res}"
    end

    res['value'].sort_by { |k,v| k}.each{|domain_name, domain|
       domain.each{|prop_name, prop|
         prop['attr'].each{|attr_name, attr|
           #output attr.to_yaml
           request = {
             'type'  => 'read',
             'mbean' => "#{domain_name}:#{prop_name}",
             'attribute' => attr_name,
           }
           base = "#{config[:scheme]}.#{ escape_metric_name(request['mbean'])}.#{ escape_metric_name(request['attribute'])}"
           output "{\"type\": \"read\",  \"mbean\": \"#{request['mbean']}\",  \"attribute\": \"#{request['attribute']}\"}" 

           begin
             res2 = post_url([config[:url], 'jolokia'].join('/'), request)
           rescue Exception => e
             output "#{base} Error: #{e}"
             next
           end
           if res2['status'] == 200
              deep_output("#{base}", res2['value'], res2['timestamp'] )
           else
              output "#{base}", 'ERROR:',  res2['error']
           end
         } if prop.key?('attr')
       }
    }

  end


  def escape_metric_name(name)
    res = name.dup
    [ 
      ['"',                     ''],
#      [/\d+[.]\d+[.]\d+[.]\d+/, "-"], # we can have several applications on the same host
#      [/port=\d\d\d\d/,         "port=-"],
#      [/-\d\d\d\d/,             "--"],
      ['*',                     '_'],
      ['.',                     '_'],
      [',',                     '.'],
      [' ',                     '_'],
      ['(',                     ''],
      [')',                     ''],
      [':',                     '.'],
    ].each {|replacement| res.gsub!(replacement[0], replacement[1])}
    return res
  end

  def deep_output(basic_name, input, timestamp)
    mapper = { 'UP' => 1, 'DOWN' => 0, 'STARTED'=>1}

    case input
    when Hash
      input.each {|key, value|
        deep_output("#{basic_name}.#{escape_metric_name(key)}", value, timestamp)
      }
    when Numeric
      output        "#{basic_name}", input, timestamp
    when String
      output        "#{basic_name}", mapper[input], timestamp if mapper.key?(input)
    end
    
  end

  def get_bean (mbean, attribute='')
    get_url ([config[:url], config[:path], mbean].compact.join('/'))
  end

  def get_url (url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
       http.use_ssl = true
       http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(config[:user], config[:password]) if config[:user]
    output "DEBUG:", uri, "\n" if config[:debug]

    begin
      res = Timeout.timeout(config[:timeout]) do
        http.request(req)
      end
    rescue Timeout::Error
      raise "Jolokia connection timed out. #{uri} "
    rescue => e
      raise "Jolokia connection error:  #{uri} #{e.message}"
    end

    case res.code
    when /^2/
      begin
        json = JSON.parse(res.body)
      rescue JSON::ParserError
        raise "Jolokia returns invalid JSON. url = #{uri} "
      end
    else
      raise "Jolokia endpoint inaccessible (#{res.code}). url = #{uri}"
    end
  end

  def post_url (url, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
       http.use_ssl = true
       http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    header = {'Content-Type' => 'text/json'}
    req = Net::HTTP::Post.new(uri.request_uri, header)
    req.basic_auth(config[:user], config[:password]) if config[:user]
    req.body = payload.to_json
    output "DEBUG:", uri, "\n" if config[:debug]

    begin
      res = Timeout.timeout(config[:timeout]) do
        http.request(req)
      end
    rescue Timeout::Error
      raise "Jolokia connection timed out. #{uri} "
    rescue => e
      raise "Jolokia connection error:  #{uri} #{e.message}"
    end

    case res.code
    when /^2/
      begin
        json = JSON.parse(res.body)
      rescue JSON::ParserError
        raise "Jolokia returns invalid JSON. url = #{uri} "
      end
    else
      raise "Jolokia endpoint inaccessible (#{res.code}). url = #{uri}"
    end
  end

end


