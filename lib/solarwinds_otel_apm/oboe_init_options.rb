# Copyright (c) 2019 SolarWinds, LLC.
# All rights reserved.

require 'singleton'

module SolarWindsOTelAPM

  class OboeInitOptions
    include Singleton

    attr_reader :reporter, :host, :service_name, :ec2_md_timeout, :grpc_proxy # exposing these mainly for testing

    def initialize
      # optional hostname alias
      @hostname_alias = ENV['SW_APM_HOSTNAME_ALIAS'] || ''
      # level at which log messages will be written to log file (0-6)
      @debug_level = (ENV['SW_APM_DEBUG_LEVEL'] || 3).to_i
      # file name including path for log file
      # TODO eventually find better way to combine ruby and oboe logs
      @log_file_path = ENV['SW_APM_LOGFILE'] || ''
      # maximum number of transaction names to track
      @max_transactions = (ENV['SW_APM_MAX_TRANSACTIONS'] || -1).to_i
      # maximum wait time for flushing data before terminating in milli seconds
      @max_flush_wait_time = (ENV['SW_APM_FLUSH_MAX_WAIT_TIME'] || -1).to_i
      # events flush timeout in seconds (threshold for batching messages before sending off)
      @events_flush_interval = (ENV['SW_APM_EVENTS_FLUSH_INTERVAL'] || -1).to_i
      # events flush batch size in KB (threshold for batching messages before sending off)
      @event_flush_batch_size = (ENV['SW_APM_EVENTS_FLUSH_BATCH_SIZE'] || -1).to_i

      # the reporter to be used (ssl, upd, file, null)
      # collector endpoint (reporter=ssl), udp address (reporter=udp), or file path (reporter=file)
      @reporter, @host = reporter_and_host

      # the service key
      @service_key = read_and_validate_service_key
      # certificate content
      @certificates = read_certificates
      # size of the message buffer
      @buffer_size = (ENV['SW_APM_BUFSIZE'] || -1).to_i
      # flag indicating if trace metrics reporting should be enabled (default) or disabled
      @trace_metrics = (ENV['SW_APM_TRACE_METRICS'] || -1).to_i
      # the histogram precision (only for ssl)
      @histogram_precision = (ENV['SW_APM_HISTOGRAM_PRECISION'] || -1).to_i
      # custom token bucket capacity
      @token_bucket_capacity = (ENV['SW_APM_TOKEN_BUCKET_CAPACITY'] || -1).to_i
      # custom token bucket rate
      @token_bucket_rate = (ENV['SW_APM_TOKEN_BUCKET_RATE'] || -1).to_i
      # use single files in file reporter for each event
      @file_single = (ENV['SW_APM_REPORTER_FILE_SINGLE'].to_s.downcase == 'true') ? 1 : 0
      # timeout for ec2 metadata
      @ec2_md_timeout = read_and_validate_ec2_md_timeout
      @grpc_proxy = read_and_validate_proxy
      # hardcoded arg for lambda (lambda not supported yet)
      # hardcoded arg for grpc hack
      # hardcoded arg for trace id format to use w3c format
      # flag for format of metric (0 = Both; 1 = AppOptics only; 2 = SWO only; default = 0)
      @metric_format = determine_the_metric_model
    end

    def re_init # for testing with changed ENV vars
      initialize
    end

    def array_for_oboe
      [
        @hostname_alias,         # 0
        @debug_level,            # 1
        @log_file_path,          # 2
        @max_transactions,       # 3
        @max_flush_wait_time,    # 4
        @events_flush_interval,  # 5
        @event_flush_batch_size, # 6

        @reporter,               # 7
        @host,                   # 8
        @service_key,            # 9
        @certificates,           #10
        @buffer_size,            #11
        @trace_metrics,          #12
        @histogram_precision,    #13
        @token_bucket_capacity,  #14
        @token_bucket_rate,      #15
        @file_single,            #16
        @ec2_md_timeout,         #17
        @grpc_proxy,             #18
        0,                       #19 arg for lambda (no lambda for ruby yet)
        @metric_format           #22
      ]
    end

    def service_key_ok?
      return !@service_key.empty? || @reporter != 'ssl'
    end

    private

    def reporter_and_host

      reporter = ENV['SW_APM_REPORTER'] || 'ssl'
      # override with 'file', e.g. when running tests
      # changed my mind => set the right reporter in the env when running tests !!!
      # reporter = 'file' if ENV.key?('SW_APM_GEM_TEST')

      host = ''
      case reporter
      when 'ssl', 'file'
        host = ENV['SW_APM_COLLECTOR'] || ''
      when 'udp'
        host = ENV['SW_APM_COLLECTOR']
        # TODO decide what to do
        # ____ SolarWindsOTelAPM::Config[:reporter_host] and
        # ____ SolarWindsOTelAPM::Config[:reporter_port] were moved here from
        # ____ oboe_metal.rb and are not documented anywhere
        # ____ udp is for internal use only
      when 'null'
        host = ''
      end

      [reporter, host]
    end

    def read_and_validate_service_key
      return '' unless @reporter == 'ssl'

      service_key = ENV['SW_APM_SERVICE_KEY']
      unless service_key
        SolarWindsOTelAPM.logger.error "[solarwinds_apm/oboe_options] SW_APM_SERVICE_KEY not configured."
        return ''
      end

      match = service_key.match( /([^:]+)(:{0,1})(.*)/ )
      token = match[1]
      service_name = match[3]

      return '' unless validate_token(token)
      return '' unless validate_transform_service_name(service_name)

      return "#{token}:#{service_name}"
    end

    def validate_token(token)
      if (token !~ /^[0-9a-zA-Z_-]{71}$/) && ENV['SW_APM_COLLECTOR'] !~ /java-collector:1222/
        masked = "#{token[0..3]}...#{token[-4..-1]}"
        SolarWindsOTelAPM.logger.error "[solarwinds_apm/oboe_options] SW_APM_SERVICE_KEY problem. API Token in wrong format. Masked token: #{masked}"
        return false
      end

      true
    end

    def validate_transform_service_name(service_name)
      service_name = 'test_ssl_collector' if ENV['SW_APM_COLLECTOR'] =~ /java-collector:1222/
      if service_name.empty?
        SolarWindsOTelAPM.logger.error "[solarwinds_apm/oboe_options] SW_APM_SERVICE_KEY problem. Service Name is missing"
        return false
      end

      name = service_name.dup
      name.downcase!
      name.gsub!(/[^a-z0-9.:_-]/, '')
      name = name[0..254]

      if name != service_name
        SolarWindsOTelAPM.logger.warn "[solarwinds_apm/oboe_options] SW_APM_SERVICE_KEY problem. Service Name transformed from #{service_name} to #{name}"
        service_name = name
      end
      @service_name = service_name # instance variable used in testing
      true
    end

    def read_and_validate_ec2_md_timeout
      timeout = ENV['SW_APM_EC2_METADATA_TIMEOUT']
      return 1000 unless timeout.is_a?(Integer) || timeout =~ /^\d+$/
      timeout = timeout.to_i
      return timeout.between?(0, 3000) ? timeout : 1000
    end

    def read_and_validate_proxy
      proxy = ENV['SW_APM_PROXY'] || ''
      return proxy if proxy == ''

      unless proxy =~ /http:\/\/.*:\d+$/
        SolarWindsOTelAPM.logger.error "[solarwinds_apm/oboe_options] SW_APM_PROXY/http_proxy doesn't start with 'http://', #{proxy}"
        return '' # try without proxy, it may work, shouldn't crash but may not report
      end

      proxy
    end

    def read_certificates

      file = ''
      file = "#{File.expand_path File.dirname(__FILE__)}/cert/star.appoptics.com.issuer.crt" if is_appoptics_collector
      file = ENV['SW_APM_TRUSTEDPATH'] if (!ENV['SW_APM_TRUSTEDPATH'].nil? && !ENV['SW_APM_TRUSTEDPATH']&.empty?)
      
      return String.new if file.empty?
      
      begin
        certificate = File.open(file,"r").read
      rescue StandardError => e
        SolarWindsOTelAPM.logger.error "[solarwinds_otel_apm/oboe_options] certificates: #{file} doesn't exist or caused by #{e.message}."
        certificate = String.new
      end
      
      return certificate

    end

    def determine_the_metric_model
      if is_appoptics_collector
        return 1
      else
        return 0
      end
    end

    def is_appoptics_collector
      begin
        sanitized_url = URI(ENV['SW_APM_COLLECTOR']).path
        return true if sanitized_url.include? "appoptics.com"
      rescue StandardError => e
        SolarWindsOTelAPM.logger.error "[solarwinds_otel_apm/oboe_options] the SW_APM_COLLECTOR is not in correct format caused by #{e.message}"
      end
      return false
    end


  end
end

