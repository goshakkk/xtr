module Xtr
  class Market
    # An orderbook order.
    class Order
      attr_reader :account, :market, :direction, :price, :quantity, :uuid,
        :reserve_id, :remainder, :fills, :status, :created_at, :canceled_at

      delegate :convert_quantity, to: :market

      # Initialize a new +Order+.
      #
      # @param account [Account] account that initiated an order
      # @param market [Market] market to create order in
      # @param direction [Symbol] order direction (+:buy+ or +:sell+)
      # @param price [BigDecimal]
      # @param quantity [Numeric]
      # @param uuid [String] order identifier
      def initialize(account, market, direction, price, quantity, uuid = Util.uuid)
        @account = account
        @market = market
        @direction = direction
        @price = Util.big_decimal(price)
        @quantity = convert_quantity(quantity)
        @remainder = @quantity
        @fills = []
        @filled = false
        @status = :initialized
        @uuid = uuid
        @created_at = Time.now
      end

      # Check if order direction is +:buy+.
      def buy?
        direction == :buy
      end

      # Check if order direction is +:sell+.
      def sell?
        direction == :sell
      end

      # Check if order is new.
      def new?
        status == :new
      end

      # Check if order is filled.
      def filled?
        status == :filled
      end

      # Check if order is paertially filled.
      def partially_filled?
        status == :partially_filled
      end

      # Check if order is rejected.
      def rejected?
        status == :rejected
      end

      # Check if order is canceled.
      def canceled?
        status == :canceled
      end

      # Check if the order isn't filled.
      def unfilled?
        new? || partially_filled?
      end

      # Calculate offered amount.
      #
      # @param price [BigDecimal]
      # @param quantity [Numeric]
      #
      # @return [Numeric]
      def offered_amount(price = price, quantity = quantity)
        buy? ? price * quantity : quantity
      end

      # Get the offered instrument symbol.
      #
      # @return [Symbol]
      def offered
        buy? ? market.right.name : market.left.name
      end

      # Calculate received amount.
      #
      # @param price [BigDecimal]
      # @param quantity [Numeroc]
      #
      # @return [Numeric]
      def received_amount(price = price, quantity = quantity)
        sell? ? price * quantity : quantity
      end

      # Get the received instrument symbol.
      #
      # @return [Symbol]
      def received
        sell? ? market.right.name : market.left.name
      end

      # Reserve the order amount.
      def reserve
        @reserve_id = account.reserve(offered, offered_amount)
        account.open_orders << self
      end

      # Release the order amount.
      def release(amount = nil)
        @reserve_id = account.release(offered, reserve_id, amount) if reserve_id
      end

      # Debit the reserved order amount.
      def debit(amount = nil)
        @reserve_id = account.debit_reserved(offered, reserve_id, amount) if reserve_id
      end

      # Credit received amount in received instrument.
      def credit(amount = received_amount)
        account.credit(received, amount)
      end

      # Release order amount and remove from account's open orders if it
      # is filled or canceled.
      def release_delete
        if filled? || canceled?
          release
          account.open_orders.delete(self)
        end
      end

      # Fill the order with +amount+ at +price+.
      #
      # @param amount [BigDecimal]
      # @param price [BigDecimal]
      def add_fill(amount, price)
        @fills << [price, amount]
        @remainder -= amount

        @status = remainder == 0 ? :filled : :partially_filled

        release_delete
      end

      # Cancel the order.
      def cancel!
        @status = :canceled
        @canceled_at = Time.now
        release_delete
      end

      # Change status from initialized to new.
      # Reserve the funds.
      #
      # @return [Boolean] whether preparation was sucessful or not
      def prepare_add
        return unless status == :initialized

        reserve
        @status = :new
        true
      rescue NotEnoughFundsError
        @status = :rejected
        false
      end

      # Get order type.
      #
      # @return [Symbol]
      def type
        :LMT
      end

      def as_json
        {
          id: uuid,
          market: market.to_s,
          direction: direction,
          price: Util.number_to_string(price),
          quantity: Util.number_to_string(quantity),
          remainder: Util.number_to_string(remainder),
          status: status,
          created_at: created_at.to_s
        }
      end

      def inspect
        "#<#{self.class.name} market=#{market.pair} dir=#{direction} price=#{Util.number_to_string(price)} qty=#{Util.number_to_string(quantity)} remainder=#{Util.number_to_string(remainder)} id=#{uuid} account=#{account.uuid}>"
      end

      def to_s
        "(#{market.pair} #{Util.number_to_string(price)} x #{Util.number_to_string(quantity)} (left: #{Util.number_to_string(remainder)}), #{account.uuid})"
      end
    end
  end
end
