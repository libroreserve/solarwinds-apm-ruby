module SolarWindsOTelAPM
  module OpenTelemetry
    # SolarWindsTxnNameManager
    class SolarWindsTxnNameManager
      def initialize
        @cache = {}
      end

      def get(key)
        @cache[key]
      end

      def del(key)
        @cache.delete(key)
      end

      def set(key, value)
        SolarWindsOTelAPM.logger.debug "############## current cache #{@cache.inspect}"
        @cache[key] = value
      end

      alias []= set
    end
  end
end