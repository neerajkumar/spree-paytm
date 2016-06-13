module Spree
  class PaytmController < StoreController
    protect_from_forgery only: :index
    
    def index
      payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
      order = current_order
      @param_list = Hash.new
      @param_list['MID'] = payment_method.preferred_merchant_id
      @param_list['INDUSTRY_TYPE_ID'] = payment_method.preferred_industry_type_id
      @param_list['CHANNEL_ID'] = payment_method.preferred_channel_id
      @param_list['WEBSITE'] = payment_method.preferred_website
      @param_list['REQUEST_TYPE'] = payment_method.request_type
      @param_list['ORDER_ID'] = payment_method.txnid(order)
      @param_list['TXN_AMOUNT'] = order.total.to_s

      if(address = current_order.bill_address || current_order.ship_address)
        phone = address.phone
      end
      #if user is not loggedin, Passing phone as customer id
      cust_id = spree_current_user.nil? ? phone : spree_current_user.id
      @param_list['CUST_ID'] = cust_id
      @param_list['MOBILE_NO'] = phone
      @param_list['EMAIL'] = order.email

      checksum = payment_method.new_pg_checksum(@param_list)
      @param_list['CHECKSUMHASH'] = checksum
      @paytm_txn_url = payment_method.txn_url
    end

    def confirm
      payment_method = Spree::PaymentMethod.find_by(type: Spree::Gateway::Paytm)
      checksum_hash = params["CHECKSUMHASH"]
      params.delete("CHECKSUMHASH")
      @is_valid_checksum = payment_method.new_pg_verify_checksum(params, checksum_hash)
      @status = params["STATUS"]
      @orderid = params["ORDERID"]
      @order = current_order || Spree::Order.find_by(number: @orderid.split("-").last)
      @payment = @order.payments.find_or_create_by(payment_method: payment_method)
      @payment.amount = @order.total
      @payment.response_code = params["RESPCODE"]
      if @is_valid_checksum
        if @status == "TXN_SUCCESS"
          @payment.state = "completed"
          @payment.save
          @order.next
          @message = Spree.t(:order_processed_successfully)
          @current_order = nil
          flash.notice = Spree.t(:order_processed_successfully)
          flash['order_completed'] = true
          @error = false
          @redirect_path = "http://dev.meltingfoods.in/orders/#{@order.number}"
        else
          @payment.state = "failed"
          @payment.save
          @order.update_attributes(payment_state: "failed")
          @error = true
          @message = "There was an error processing your payment"
          @redirect_path = "/orders/#{@order.number}"
        end
      else
        @payment.state = "invalid"
        @payment.save
        @order.update_attributes(payment_state: "invalid")
        @message = "The response did not authenticate."
        @error = true
        @redirect_path = "/orders/#{@order.number}"
      end
    end
  end
end