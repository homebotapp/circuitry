module Circuitry
  module Locks
    module Base
      DEFAULT_SOFT_TTL = (15 * 60).freeze       # 15 minutes
      DEFAULT_HARD_TTL = (24 * 60 * 60).freeze  # 24 hours

      attr_reader :soft_ttl, :hard_ttl

      def initialize(options = {})
        self.soft_ttl = options.fetch(:soft_ttl, DEFAULT_SOFT_TTL)
        self.hard_ttl = options.fetch(:hard_ttl, DEFAULT_HARD_TTL)
      end

      def soft_lock(id)
        lock(lock_key(id), soft_ttl)
      end

      def hard_lock(id)
        lock(lock_key(id), hard_ttl)
      end

      def locked?(id)
        expires_at = ttl(lock_key(id))
        expires_at && expires_at >= Time.now
      end

      def reap
        raise NotImplementedError
      end

      protected

      def lock(key, ttl)
        raise NotImplementedError
      end

      def ttl(key)
        raise NotImplementedError
      end

      private

      attr_writer :soft_ttl, :hard_ttl

      def lock_key(id)
        "circuitry:lock:#{id}"
      end
    end
  end
end
