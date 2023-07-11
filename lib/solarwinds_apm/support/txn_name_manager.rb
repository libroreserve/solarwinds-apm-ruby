module SolarWindsAPM
  module OpenTelemetry
    # SolarWindsTxnNameManager
    class TxnNameManager
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
        SolarWindsAPM.logger.debug "############## current cache #{@cache.inspect}"
        @cache[key] = value
      end

      alias []= set
    end
  end
end