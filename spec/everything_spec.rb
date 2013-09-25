require 'spec_helper'
require 'matchers'
require 'base64'
require 'ostruct'
require 'nokogiri'

describe Endicia do

  context '.get_label' do
    it "use test server url if :Test option is YES" do
      expect_request_url(the_test_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "YES")
    end

    it "use production server url if :Test option is NO" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "NO")
    end

    it "use production server url if passed no :Test option" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label
    end

    it "break 9-digit zip codes into two fields" do
      expect_label_request_body_with do |doc|
        doc.at_css("LabelRequest > ToPostalCode").content == "12345"
        doc.at_css("LabelRequest > ToZIP4").content == "6789"
      end

      Endicia.get_label(:ToPostalCode => "12345-6789")
    end

    it "send insurance option to endicia" do
      %w(OFF ON UspsOnline Endicia).each do |value|
        expect_label_request_body_with do |doc|
          !doc.css("LabelRequest > Services[InsuredMail=#{value}]").empty?
        end
        Endicia.get_label({ :InsuredMail => value })
      end
    end

    it "raise if requesting insurance for jewelry to an excluded zip" do
      %w(10036 10017 94102 94108).each do |zip|
        options = { :InsuredMail => "Endicia", :ToPostalCode => zip, :Jewelry => true }
        expect {Endicia.get_label(options) }.to raise_error Endicia::InsuranceError
      end
    end

    it "not include Jewelry in request XML" do
      options = { :InsuredMail => nil, :Jewelry => true }
      expect_label_request_body_with { |doc| doc.xpath("//Jewelry").empty? }
      Endicia.get_label(options)
    end

    it "return an Endicia::Label object" do
      Endicia.get_label.should be_a Endicia::Label
    end

    it "save the request body on the returned label object" do
      request_body = nil
      Endicia.should_receive(:post).with do |url, params|
        request_body = params[:body]
      end.and_return(fake_response)

      the_label = Endicia.get_label
      request_body.should eq the_label.request_body
    end

    it "save the request url to the returned label object" do
      request_url = nil
      Endicia.should_receive(:post).with do |url, params|
        request_url = url
      end.and_return(fake_response)

      the_label = Endicia.get_label
      request_url.should eq the_label.request_url
    end
  end

  context 'root node attributes on .get_label request' do
    before :each do
      @request_url = "http://test.com"
      Endicia.stub(:label_service_url) {@request_url}
    end

    it "passes LabelType option" do
      assert_label_request_attributes("LabelType", %w(Express CertifiedMail Priority))
    end

    it "sets LabelType attribute to Default by default" do
      expect_label_request_attribute("LabelType", "Default")
      Endicia.get_label
    end

    it "passes Test option" do
      assert_label_request_attributes("Test", %w(YES NO))
    end

    it "passes LabelSize option" do
      assert_label_request_attributes("LabelSize", %w(4x6 6x4 7x3))
    end

    it "passes ImageFormat option" do
      assert_label_request_attributes("ImageFormat", %w(PNG GIFT PDF))
    end
  end

  context 'Label' do
    before :each do
      # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf
      # Table 3-2: LabelRequestResponse XML Elements
      @response = fake_response({
        "LabelRequestResponse" => {
          "Status" => 123,
          "ErrorMessage" => "If there's an error it would be here",
          "Base64LabelImage" => Base64.encode64("the label image"),
          "TrackingNumber" => "abc123",
          "PIC" => "abcd1234",
          "FinalPostage" => 1.2,
          "TransactionID" => 1234,
          "TransactionDateTime" => "20110102030405",
          "CostCenter" => 12345,
          "ReferenceID" => "abcde12345",
          "PostmarkDate" => "20110102",
          "PostageBalance" => 3.4
        }
      })
    end

    it "initializes with relevant data from an endicia api response without error" do
      Endicia::Label.new(@response)
    end

    it "includes response body" do
      @response.stub(:body) {"the response body"}
      the_label = Endicia::Label.new(@response)
      the_label.response_body.should eq "the response body"
    end

    it "strip image data from #response_body" do
      @response.stub(:body) {"<data><one>two</one><Base64LabelImage>binary data</Base64LabelImage></data>"}
      the_label = Endicia::Label.new(@response)
      the_label.response_body.should eq "<data><one>two</one><Base64LabelImage>[data]</Base64LabelImage></data>"
    end
  end

  context 'defaults in rails' do
    it "load from config/endicia.yml" do
      attrs = {
        :AccountID   => 123,
        :RequesterID => "abc",
        :PassPhrase  => "123",
      }

      with_rails_endicia_config(attrs) do
        Endicia.defaults.should eq attrs
      end
    end

    it "support root node request attributes" do
      attrs = {
        :Test        => "YES",
        :LabelType   => "Priority",
        :LabelSize   => "6x4",
        :ImageFormat => "PNG"
      }

      with_rails_endicia_config(attrs) do
        attrs.each do |key, value|
          expect_label_request_attribute(key, value)
          Endicia.get_label
        end
      end
    end
  end

  context '.change_pass_phrase(new, options)' do
    it 'make a ChangePassPhraseRequest call to the Endicia API' do
      Endicia.stub(:label_service_url) {"http://example.com/api"}
      Time.any_instance.stub(:to_f) {"timestamp"}

      Endicia.should_receive(:post).with do |request_url, options|
        request_url == "http://example.com/api/ChangePassPhraseXML" &&
        options[:body] &&
        options[:body].match(/changePassPhraseRequestXML=(.+)/) do |match|
          doc = Nokogiri::Slop(match[1])
          doc.ChangePassPhraseRequest &&
          doc.ChangePassPhraseRequest.RequesterID.content == "abcd" &&
          doc.ChangePassPhraseRequest.RequestID.content == "CPPtimestamp" &&
          doc.ChangePassPhraseRequest.CertifiedIntermediary.AccountID.content == "123456" &&
          doc.ChangePassPhraseRequest.CertifiedIntermediary.PassPhrase.content == "oldPassPhrase" &&
          doc.ChangePassPhraseRequest.NewPassPhrase.content == "newPassPhrase"
        end
      end.and_return(fake_response)

      Endicia.change_pass_phrase("newPassPhrase", {
        :PassPhrase => "oldPassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end

    it 'use credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "old_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.should_receive(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/changePassPhraseRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.ChangePassPhraseRequest &&
            doc.ChangePassPhraseRequest.RequesterID.content == "efgh" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.PassPhrase.content == "old_phrase"
          end
        end.and_return(fake_response)

        Endicia.change_pass_phrase("new")
      end
    end

    it 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new", { :Test => "YES" })
    end

    it 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new")
    end

    it 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("ChangePassPhraseXML"))
        Endicia.change_pass_phrase("new")
      end
    end

    it "include response body in return hash" do
      response = double :response
      response.stub(:[])
      response.stub(:body) {"the response body"}
      Endicia.stub(:post) {response}
      result = Endicia.change_pass_phrase("new")
      result[:response_body].should eq "the response body"
    end

    context 'when successful' do
      before :each do
        Endicia.stub(:post) {fake_response({
          "ChangePassPhraseRequestResponse" => { "Status" => "0" }
        })}
      end

      it 'return hash with :success => true' do
        result = Endicia.change_pass_phrase("new_phrase")
        result[:success].should be true
      end
    end

    context 'when not successful' do
      before :each do
        Endicia.stub(:post) {fake_response({
          "ChangePassPhraseRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        })}
      end

      it 'returns hash with :success => false' do
        result = Endicia.change_pass_phrase("new_phrase")
        result[:success].should be false
      end

      it 'returns hash with an :error_message' do
        result = Endicia.change_pass_phrase("new_phrase")
        result[:error_message].should eq "the error message"
      end
    end
  end

  context '.buy_postage(amount)' do
    it 'make a BuyPostage call to the Endicia API' do
      Endicia.stub(:label_service_url) {"http://example.com/api"}
      Time.any_instance.stub(:to_f) {"timestamp"}

      Endicia.should_receive(:post).with do |request_url, options|
        request_url == "http://example.com/api/BuyPostageXML" &&
        options[:body] &&
        options[:body].match(/recreditRequestXML=(.+)/) do |match|
          doc = Nokogiri::Slop(match[1])
          doc.RecreditRequest &&
          doc.RecreditRequest.RequesterID.content == "abcd" &&
          doc.RecreditRequest.RequestID.content == "BPtimestamp" &&
          doc.RecreditRequest.CertifiedIntermediary.AccountID.content == "123456" &&
          doc.RecreditRequest.CertifiedIntermediary.PassPhrase.content == "PassPhrase" &&
          doc.RecreditRequest.RecreditAmount.content == "125.99"
        end
      end.and_return(fake_response)

      Endicia.buy_postage("125.99", {
        :PassPhrase => "PassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end

    it 'uses credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.should_receive(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/recreditRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.RecreditRequest &&
            doc.RecreditRequest.RequesterID.content == "efgh" &&
            doc.RecreditRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.RecreditRequest.CertifiedIntermediary.PassPhrase.content == "my_phrase"
          end
        end.and_return(fake_response)

        Endicia.buy_postage("100")
      end
    end

    it 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("BuyPostageXML"))
      Endicia.buy_postage("100", { :Test => "YES" })
    end

    it 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("BuyPostageXML"))
      Endicia.buy_postage("100")
    end

    it 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("BuyPostageXML"))
        Endicia.buy_postage("100")
      end
    end

    it "include response body in return hash" do
      response = double :response
      response.stub(:[])
      response.stub(:body) {"the response body"}
      Endicia.stub(:post) {response}
      result = Endicia.buy_postage("100")
      result[:response_body].should eq "the response body"
    end

    context 'when successful' do
      before :each do
        Endicia.stub(:post) {fake_response({
          "RecreditRequestResponse" => { "Status" => "0" }
        })}
      end

      it 'returns hash with :success => true' do
        result = Endicia.buy_postage("100")
        result[:success].should be true
      end
    end

    context 'when not successful' do
      before :each do
        Endicia.stub(:post) {fake_response({
          "RecreditRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        })}
      end

      it 'return hash with :success => false' do
        result = Endicia.buy_postage("100")
        result[:success].should be false
      end

      it 'return hash with an :error_message' do
        result = Endicia.buy_postage("100")
        result[:error_message].should eq "the error message"
      end
    end
  end

  context '.status_request(tracking_number, options)' do
    it 'makes a StatusRequest call to the Endicia API' do
      Endicia.should_receive(:get).with do |els_service_url|
        regex = /http.+&method=StatusRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.StatusRequest &&
          doc.StatusRequest.AccountID.content == "123456" &&
          doc.StatusRequest.PassPhrase.content == "PassPhrase" &&
          doc.StatusRequest.Test.content == "YES" &&
          doc.StatusRequest.StatusList.PICNumber.content == "the tracking number"
        end
      end.and_return(fake_response)

      Endicia.status_request("the tracking number", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end

    it 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }

      with_rails_endicia_config(attrs) do
        Endicia.should_receive(:get).with do |els_service_url|
          regex = /http.+&method=StatusRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.StatusRequest.Test.content == "YES" &&
            doc.StatusRequest.AccountID.content == "456789" &&
            doc.StatusRequest.PassPhrase.content == "my_phrase"
          end
        end.and_return(fake_response)
        Endicia.status_request("the tracking number")
      end
    end

    it "include response body in return hash" do
      response = double :response
      response.stub(:[])
      response.stub(:body) {"the response body"}
      Endicia.stub(:get) {response}
      result = Endicia.status_request("the tracking number")
      result[:response_body].should eq "the response body"
    end

    it "allow you to request full status" do
      response_body = "" + <<-EOXML
<StatusResponse>
  <AccountID>987654</AccountID>
  <ErrorMsg/>
    <StatusList>
      <PICNumber>1234567890987654321234
        <Status>Your item was delivered at 11:06 AM on 01/14/2012 in WANTHAM MA 02492.</Status>
          <StatusBreakdown>
            <Status_1>Out for Delivery  January 14  2012  9:07 am  WANTHAM  MA 02492</Status_1>
            <Status_2>Sorting Complete  January 14  2012  8:57 am  WANTHAM  MA 02492</Status_2>
            <Status_3>Arrival at Post Office  January 14  2012  8:27 am  WANTHAM  MA 02492</Status_3>
            <Status_4>Processed at USPS Origin Sort Facility  January 13  2012  12:19 am  NASHUA  NH 03063</Status_4>
            <Status_5>Dispatched to Sort Facility  January 12  2012  5:02 pm  KILLINGTON  VT 05751</Status_5>
            <Status_6>Acceptance  January 12  2012  3:58 pm  KILLINGTON  VT 05751</Status_6>
            <Status_7>Electronic Shipping Info Received  January 10  2012</Status_7>
          </StatusBreakdown>
        <StatusCode>D</StatusCode>
      </PICNumber>
    </StatusList>
</StatusResponse>
      EOXML
      response = double :response
      response.stub(:[])
      response.stub(:body) {response_body}
      Endicia.stub(:get) {response}
      result = Endicia.status_request("1234567890987654321234")
      result[:success].should == true
      result[:status].should == "Your item was delivered at 11:06 AM on 01/14/2012 in WANTHAM MA 02492."
      result[:status_code].should == "D"
    end

    context 'when successful' do
      before :each do
        Endicia.stub(:get) {fake_response(
          { "StatusResponse" => {} },
          "<Status>the status message</Status>
          <StatusCode>A</StatusCode>")}
      end

      it 'include :success => true in returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:success].should be true
      end

      it 'include status message in returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:status].should eq "the status message"
      end
    end

    context 'when not successful' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "StatusResponse" => {
            "ErrorMsg" => "I played your man and he died."
          }
        })}
      end

      it 'include :success => false in the returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:success].should be false
      end

      it 'include error message in the returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:error_message].should eq "I played your man and he died."
      end
    end

    context 'when tracking code is not found' do
      before :each do
        Endicia.stub(:get) {fake_response(
          { "StatusResponse" => {} },
          "<Status>not found</Status>
          <StatusCode>-1</StatusCode>")}
      end

      it 'include :success => false in the returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:success].should be false
      end

      it 'include status message in returned hash' do
        result = Endicia.status_request("the tracking number")
        result[:status].should eq "not found"
      end
    end
  end

  context '.refund_request(tracking_number, options)' do
    it 'make a RefundRequest call to the Endicia API' do
      Endicia.should_receive(:get).with do |els_service_url|
        regex = /http.+&method=RefundRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.RefundRequest &&
          doc.RefundRequest.AccountID.content == "123456" &&
          doc.RefundRequest.PassPhrase.content == "PassPhrase" &&
          doc.RefundRequest.Test.content == "YES" &&
          doc.RefundRequest.RefundList.PICNumber.content == "the tracking number"
        end
      end.and_return(fake_response)

      Endicia.refund_request("the tracking number", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end

    it 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }

      with_rails_endicia_config(attrs) do
        Endicia.should_receive(:get).with do |els_service_url|
          regex = /http.+&method=RefundRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.RefundRequest.Test.content == "YES" &&
            doc.RefundRequest.AccountID.content == "456789" &&
            doc.RefundRequest.PassPhrase.content == "my_phrase"
          end
        end.and_return(fake_response)
        Endicia.refund_request("the tracking number")
      end
    end

    it "include response body in return hash" do
      response = double :response
      response.stub(:[])
      response.stub(:body) {"the response body"}
      Endicia.stub(:get) {response}
      result = Endicia.refund_request("the tracking number")
      result[:response_body].should eq "the response body"
    end

    context 'when successful' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "RefundResponse" => {
            "ErrorMsg" => nil,
            "FormNumber" => 567890,
            "RefundList" => {
              "PICNumber" => %Q{
                the tracking number
                <IsApproved>YES</IsApproved>
                <ErrorMsg>Approved - Less than 10 days.</ErrorMsg>
              }
            }
          }
        })}
      end

      it 'include :success => true in returned hash' do
        result = Endicia.refund_request("the tracking number")
        result[:success].should be true
      end

      it 'include error_message in response' do
        result = Endicia.refund_request("the tracking number")
        result[:error_message].should eq 'Approved - Less than 10 days.'
      end

      it 'include form_number in response' do
        result = Endicia.refund_request("the tracking number")
        result[:form_number].should eq 567890
      end
    end

    context 'when login not successful' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "RefundResponse" => {
            "ErrorMsg" => "I played your man and he died."
          }
        })}
      end

      it 'include :success => false in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        result[:success].should be false
      end

      it 'include error message in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        result[:error_message].should eq "I played your man and he died."
      end
    end

    context 'when refund not successful' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "RefundResponse" => {
            "ErrorMsg" => nil,
            "FormNumber" => nil,
            "RefundList" => {
              "PICNumber" => %Q{
                the tracking number
                <IsApproved>NO</IsApproved>
                <ErrorMsg>Denied - Must be within 10 days.</ErrorMsg>
              }
            }
          }
        })}
      end

      it 'includes :success => false in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        result[:success].should be false
      end

      it 'includes error message in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        result[:error_message].should eq "Denied - Must be within 10 days."
      end
    end
  end

  context '.carrier_pickup_request(tacking_number, package_location, options)' do
    it 'make a CarrierPickupRequest call to the Endicia API' do
      Endicia.should_receive(:get).with do |els_service_url|
        regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.CarrierPickupRequest &&
          doc.CarrierPickupRequest.AccountID.content == "123456" &&
          doc.CarrierPickupRequest.PassPhrase.content == "PassPhrase" &&
          doc.CarrierPickupRequest.Test.content == "YES" &&
          doc.CarrierPickupRequest.PackageLocation.content == "sd" &&
          doc.CarrierPickupRequest.PickupList.PICNumber.content == "the tracking number"
        end
      end.and_return(fake_response)

      Endicia.carrier_pickup_request("the tracking number", "sd", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end

    it 'accept custom pickup address' do
      Endicia.should_receive(:get).with do |els_service_url|
        regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.CarrierPickupRequest.UseAddressOnFile.content == "N" &&
          doc.CarrierPickupRequest.FirstName.content == "Slick" &&
          doc.CarrierPickupRequest.LastName.content == "Nick" &&
          doc.CarrierPickupRequest.CompanyName.content == "Hair Product, Inc." &&
          doc.CarrierPickupRequest.SuiteOrApt.content == "Apt. 123" &&
          doc.CarrierPickupRequest.Address.content == "123 Fake Street" &&
          doc.CarrierPickupRequest.City.content == "Orlando" &&
          doc.CarrierPickupRequest.State.content == "FL" &&
          doc.CarrierPickupRequest.ZIP5.content == "12345" &&
          doc.CarrierPickupRequest.ZIP4.content == "1234" &&
          doc.CarrierPickupRequest.Phone.content == "1234567890" &&
          doc.CarrierPickupRequest.Extension.content == "12345"
        end
      end.and_return(fake_response)

      Endicia.carrier_pickup_request("the tracking number", "sd", {
        :UseAddressOnFile => "N",
        :FirstName => "Slick",
        :LastName => "Nick",
        :CompanyName => "Hair Product, Inc.",
        :SuiteOrApt => "Apt. 123",
        :Address => "123 Fake Street",
        :City => "Orlando",
        :State => "FL",
        :ZIP5 => "12345",
        :ZIP4 => "1234",
        :Phone => "1234567890",
        :Extension => "12345"
      })
    end

    it 'accepts custom pickup location' do
      Endicia.should_receive(:get).with do |els_service_url|
        regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.CarrierPickupRequest.PackageLocation.content == "ot" &&
          doc.CarrierPickupRequest.SpecialInstructions.content == "the special instructions"
        end
      end.and_return(fake_response)

      Endicia.carrier_pickup_request("the tracking number", "ot", {
        :SpecialInstructions => "the special instructions"
      })
    end

    it 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }

      with_rails_endicia_config(attrs) do
        Endicia.should_receive(:get).with do |els_service_url|
          regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.CarrierPickupRequest.Test.content == "YES" &&
            doc.CarrierPickupRequest.AccountID.content == "456789" &&
            doc.CarrierPickupRequest.PassPhrase.content == "my_phrase"
          end
        end.and_return(fake_response)
        Endicia.carrier_pickup_request("the tracking number", "sd")
      end
    end

    it "include response body in return hash" do
      response = double :response
      response.stub(:[])
      response.stub(:body) {"the response body"}
      Endicia.stub(:get) {response}
      result = Endicia.carrier_pickup_request("the tracking number", "sd")
      result[:response_body].should eq "the response body"
    end

    context 'when successful' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "CarrierPickupRequestResponse" => {
            "Response" => {
              "DayOfWeek" => "Monday",
              "Date" => "11/11/2011",
              "CarrierRoute" => "C",
              "ConfirmationNumber" => "abc123"
            }
          }
        })}
      end

      it 'include :success => true in returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:success].should be true
      end

      it 'include pickup information in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:day_of_week].should eq "Monday"
        result[:date].should eq "11/11/2011"
        result[:carrier_route].should eq "C"
        result[:confirmation_number].should eq "abc123"
      end
    end

    context 'when there is an error message' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "CarrierPickupRequestResponse" => {
            "ErrorMsg" => "your ego is out of control"
          }
        })}
      end

      it 'include :success => false in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:success].should be false
      end

      it 'include error message in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:error_message].should eq "your ego is out of control"
      end
    end

    context 'when there is an error code' do
      before :each do
        Endicia.stub(:get) {fake_response({
          "CarrierPickupRequestResponse" => {
            "Response" => {
              "Error" => {
                "Number" => "123",
                "Description" => "OverThere is an invalid package location"
              }
            }
          }
        })}
      end

      it 'include :success => false in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:success].should be false
      end

      it 'include error code in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:error_code].should eq "123"
      end

      it 'include error message in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        result[:error_description].should eq "OverThere is an invalid package location"
      end
    end
  end
end
