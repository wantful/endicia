module Endicia
  class Label
    attr_accessor :image,
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
                  :requester_id,
                  :cost_center,
                  :request_body,
                  :request_url,
                  :response_body
    def initialize(result)
      self.response_body = filter_response_body(result.body.dup)
      data = result["LabelRequestResponse"] || {}
      data.each do |k, v|
        k = "image" if k == 'Base64LabelImage'
        setter = :"#{k.tableize.singularize}="
        send(setter, v) if !k['xmlns'] && respond_to?(setter)
      end
    end

    private
    def filter_response_body(string)
      # Strip image data for readability:
      string.sub(/<Base64LabelImage>.+<\/Base64LabelImage>/,
                 "<Base64LabelImage>[data]</Base64LabelImage>")
    end
  end
end
