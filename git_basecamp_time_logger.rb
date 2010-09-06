#!/usr/bin/env ruby
#
# Git post-commit hook to log dev time to Basecamp, possibly computing said
# time automatically, using Basecamp settings in the Git global config (for
# Basecamp access) and local config (for project/task info).
#
# Version 0.6 (2010-09-06)
#
# Copyright (c) 2010 Christophe Porteneuve <tdd@git-attitude.fr>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'date'
require 'net/http'
require 'net/https'
require 'tempfile'
require 'uri'

# Cherry-pick what we need from ActiveSupport…

class NilClass
  def blank?; true; end
end

class Hash
  alias_method :blank?, :empty?
end

class String
  def blank?
    self =~ /\A\s*\Z/
  end
  
  def present?
    not blank?
  end
end

class Symbol
  def to_proc
    lambda { |o| o.send(self) }
  end
end

# Our actual Git/Basecamp code

class GitBasecampTimeLogger
  GIT_GLOBAL_CONFIG_API_ENDPOINT_KEY    = 'basecamp.api-endpoint'
  GIT_GLOBAL_CONFIG_API_TOKEN_KEY       = 'basecamp.api-token'
  GIT_GLOBAL_CONFIG_PERSON_ID_KEY       = 'basecamp.person-id'

  GIT_LOCAL_CONFIG_PROJECT_ID_KEY       = 'basecamp.project-id'
  GIT_LOCAL_CONFIG_CURRENT_TASK_ID_KEY  = 'basecamp.current-task-id'
  
  # Whether to cache the account's person_id in the global Git config, to speed up later usage.
  OPT_CACHE_PERSON_ID       = true
  # Whether to amend the commit message to strip the Basecamp time-logging tag, once logging is done.
  OPT_STRIP_TAG_FROM_COMMIT = true
  
  def initialize
    setup
  end
  
  def run
    compute_duration if delta?
    @commit_hours = "%d:%02d" % [@commit_minutes / 60, @commit_minutes % 60]
    log :info, "Logging #{@commit_hours}h of work…"
    if task_mode?
      pick_task if task_unknown?
      abort :cant_pick_task if task_unknown?
      log_time_to_task
    else
      log_time_to_project
    end
    %x(git commit --amend -m "#{@msg.gsub('"', '\\"')}") if OPT_STRIP_TAG_FROM_COMMIT
  end
  
  def self.run
    new.run
  end
  
private
  ABORT_MESSAGES = {
    :default =>
      ["Some error occurred, sorry!", 42],
    :cant_pick_task =>
      ['Cannot have you pick the task as keyboard access seems to b0rk (are you on a BSD/OSX system?) -- specify the task ID.', 6],
    :cannot_use_delta =>
      ["Can’t compute a time delta: no previous commit!", 5],
    :invalid_api_token =>
      ["Invalid API token (probably): a request failed.", 1],
    :missing_api_endpoint =>
      ["Missing API endpoint: use git config --global --add #{GIT_GLOBAL_CONFIG_API_ENDPOINT_KEY} your-account-url-here", 2],
    :missing_api_token =>
      ["Missing API token: use git config --global --add #{GIT_GLOBAL_CONFIG_API_TOKEN_KEY} your-api-token-here", 3],
    :missing_project_id =>
      ["Missing project ID: use git config --add #{GIT_LOCAL_CONFIG_PROJECT_ID_KEY} your-project-id-here", 4],
  }

  TTY_COLORS = { :info => '0;37', :error => 31, :confirm => 32, :match => '4;32', :task_id => 33 }

  def abort(code)
    msg, exit_code = ABORT_MESSAGES[code]
    msg = ABORT_MESSAGES[:default][0] if msg.blank?
    exit_code = ABORT_MESSAGES[:default][-1] if exit_code.to_s.blank?
    log :error, msg
    exit exit_code
  end

  def complete_task!
    return if task_unknown?
    result = request(:put, "todo_items/#{@current_task_id}/complete")
    if result.is_a?(Net::HTTPOK)
      log :confirm, 'Task marked as completed!'
    else
      errors = result.body.scan(%r(<error>(.*?)</error>)).flatten
      if errors.empty?
        log :error, 'A non-specific error occurred, sorry.'
      else
        errors.each { |t| log :error, "* #{t}" }
      end
    end
  end

  def complete_task?
    !!@complete_task
  end

  def compute_duration
    previous_stamp = git_log_one('%ct', 1)
    abort :cannot_use_delta if previous_stamp.blank?
    @commit_minutes = ((@stamp - previous_stamp.to_i - @offset * 60) / 60.0).round
  end
  
  def delta?
    not defined?(@commit_minutes)
  end
  
  def get(url, field = nil)
    result = request(:get, url)
    return unless result.is_a?(Net::HTTPOK)
    return result.body if field.blank?
    result.body[%r(<#{field}\b[^>]*>(.*?)</#{field}>)] && $1
  end
  
  def get_candidate_tasks
    xml = get("todo_lists")
    # I don't want to depend on RubyGems and SimpleXML/Nokogiri here, so let's resort to a few shell tricks…
    xml_file = Tempfile.new('bcgitxml')
    xml_file.write xml
    xml_file.close
    first_pass = %x(sed -n '/<project-id type="integer">#{@project_id}</,/<\\/todo-list>/p' "#{xml_file.path}")
    xml_file = Tempfile.new('bcgitxml')
    xml_file.write first_pass
    xml_file.close
    items = %x(sed -n '/<todo-item>/,/<\\/todo-item>/p' "#{xml_file.path}").split('</todo-item>').reject(&:blank?)
    items.inject([]) do |acc, item|
      next acc unless item[%r(<completed type="boolean">false</completed>)]
      task_name = item[%r(<content>(.*?)</content>)] && $1.strip
      next acc unless @task_filter && @task_filter.all? { |f| task_name =~ f }
      task_id = item[%r(<id type="integer">(\d+)</id>)] && $1.to_i
      acc << [task_id, task_name]
    end
  end
  
  def git_log_one(format, skip = 0)
    %x(git log --skip=#{skip} -1 --format="#{format}").strip
  end

  def log(mode, text, *args)
    prefix = @tty && (color = TTY_COLORS[mode]) && "\033[#{color.is_a?(String) ? nil : '1;'}#{color}m" || nil
    suffix = prefix && "\033[0m" || nil
    stream = :error == mode ? STDERR : STDOUT
    if args.empty?
      stream.puts "#{prefix}#{text}#{suffix}"
    else
      stream.printf "#{prefix}#{text}#{suffix}", *args
    end
  end
  
  def log_time_to_project
    result = post("projects/#{@project_id}/time_entries", to_xml)
    if result.is_a?(Integer)
      log :confirm, 'Time logged!'
    else
      log :error, "Errors encountered:\n#{result.join("\n")}"
    end
  end
  
  def log_time_to_task
    result = post("todo_items/#{@current_task_id}/time_entries", to_xml)
    if result.is_a?(Integer)
      log :confirm, 'Time logged to task!'
      complete_task! if complete_task?
    else
      log :error, "Errors encountered:#{result.join("\n")}"
    end
  end

  def parse_latest_log
    @sha, @stamp, @msg = git_log_one('%h %ct %s').split(' ', 3).map(&:strip)
    exit 0 unless @msg[/\[BC(:T[\w\s]*X?)?(?::(-?\d+[hm]?))?\]$/i]
    @stamp = @stamp.to_i
    # Handle task segment, if any
    task_info, offset_or_duration = $1, $2.to_s
    @current_task_id = task_info.to_s[/(\d+)/] && $1
    if task_unknown? && task_info.to_s[/^:T(.*)X?$/i]
      @task_filter = $1.strip.split(/\s+/).map { |t| Regexp.new(Regexp.escape(t), Regexp::IGNORECASE) }
    end
    @complete_task = !!task_info[/X$/i]
    @task_mode = !!task_info
    # Tweak message
    @msg = @msg.sub(/\[.*?\]$/, '')
    # Process offset or duration, if any
    offset_or_duration = offset_or_duration.sub('m', '')
    if offset_or_duration[/h$/i]
      offset_or_duration = 60 * offset_or_duration[0..-2].to_i
    end
    offset_or_duration = offset_or_duration.to_i
    if offset_or_duration <= 0
      @offset = -offset_or_duration
    elsif offset_or_duration > 0
      @commit_minutes = offset_or_duration
    end
  end
  
  def pick_task
    tasks = get_candidate_tasks
    if tasks.size > 1
      log :error, "-> Too many tasks to choose from: either specify the task ID or a set of words to narrow down task descriptions"
      for (task_id, task_desc) in tasks
        prefix = @tty && "\033[1;#{TTY_COLORS[:task_id]}m" || nil
        suffix = prefix && "\033[1;#{TTY_COLORS[:error]}m" || nil
        log :error, " - #{prefix}%10d#{suffix} = %s\n", task_id, task_desc
      end
      abort :cant_pick_task
    else
      @current_task_id = tasks[0][0]
      matched_name = tasks[0][1]
      if @tty
        @task_filter && @task_filter.each { |f| matched_name.gsub!(f, "\033[1;#{TTY_COLORS[:match]}m\\&\033[0;37m") }
      end
      log :info, "-> Auto-detected single matching task: #{matched_name} (##{@current_task_id})"
    end
  end
  
  def post(url, data)
    result = request(:post, url, data)
    if result.is_a?(Net::HTTPCreated)
      result['Location'][/(\d+)$/] && $1.to_i
    else
      errors = result.body.scan(%r(<error>(.*?)</error>)).flatten
      errors.empty? ? 'A non-specific error occurred, sorry.' : errors.map { |t| "* #{t}" }
    end
  end
  
  def request(method, path, data = nil)
    url = URI.parse(@api_endpoint)
    req = Net::HTTP.const_get(method.to_s.capitalize).new("/#{path}.xml")
    req['Accept'] = req['Content-Type'] = 'application/xml'
    req.basic_auth @api_token, 'X'
    req.body = data if :get != method && data
    req['Content-Length'] = 0 if :get != method && !data
    requester = Net::HTTP.new(url.host, url.port)
    if 'https' == url.scheme
      requester.use_ssl = true
      requester.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    # requester.set_debug_output STDERR if :put == method
    requester.start do |http|
      http.request(req)
    end
  end

  def setup
    @tty = STDOUT.tty?
    parse_latest_log
    @api_endpoint = %x(git config --global --get #{GIT_GLOBAL_CONFIG_API_ENDPOINT_KEY}).strip
    abort :missing_api_endpoint if @api_endpoint.blank?
    @api_token = %x(git config --global --get #{GIT_GLOBAL_CONFIG_API_TOKEN_KEY}).strip
    abort :missing_api_token if @api_token.blank?
    @person_id = %x(git config --global --get #{GIT_GLOBAL_CONFIG_PERSON_ID_KEY}).strip if OPT_CACHE_PERSON_ID
    @person_id = get('me', 'id') if @person_id.blank?
    abort :invalid_api_token if @person_id.blank?
    %x(git config --global --replace-all #{GIT_GLOBAL_CONFIG_PERSON_ID_KEY} #{@person_id}) if OPT_CACHE_PERSON_ID
    @project_id = %x(git config --get #{GIT_LOCAL_CONFIG_PROJECT_ID_KEY}).strip
    abort :missing_project_id if @project_id.blank?
    @current_task_id = %x(git config --get #{GIT_LOCAL_CONFIG_CURRENT_TASK_ID_KEY}).strip if @current_task_id.blank?
    @task_mode ||= @current_task_id.present?
  end
  
  def task_mode?
    !!@task_mode
  end
  
  def task_unknown?
    @current_task_id.to_i <= 0
  end

  def to_xml
    msg = "#{@msg.strip} (#{@sha})"
    description = msg.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
    %(
    <time-entry>
      <person-id>#{@person_id}</person-id>
      <date>#{Date.today.strftime('%Y-%m-%d')}</date>
      <hours>#{@commit_hours}</hours>
      <description>#{description}</description>
    </time-entry>
    ).strip.gsub(/^\s+|\s+$/, '')
  end
end

GitBasecampTimeLogger.run if __FILE__ == $0