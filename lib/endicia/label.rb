module Endicia
  class Label
    attr_accessor :requester_id,
                  :image,
                  :status,
                  :tracking_number,
                  :final_postage,
                  :transaction_date_time,
                  :transaction_id,
                  :postmark_date,
                  :postage_balance,
                  :pic,
                  :error_message,
                  :reference_id,
                  :reference_id2,
                  :reference_id3,
                  :reference_id4,
                  :cost_center,
                  :request_body,
                  :request_url,
                  :response_body

    def initialize(result)
      self.response_body = result.body
      data = result["LabelRequestResponse"] || {}
      data.each do |k, v|
        k = "image" if k == 'Base64LabelImage'
        send(:"#{k.tableize.singularize}=", v) if !k['xmlns']
      end
    end
  end
end
