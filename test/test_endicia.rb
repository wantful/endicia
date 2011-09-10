require 'helper'
require 'base64'
require 'ostruct'
require 'nokogiri'

module TestEndiciaHelper
  def fake_response(hash = {}, body = "")
    hash.stubs(:body).returns(body)
    hash
  end
  
  def expect_label_request_attribute(key, value, returns = fake_response)
    Endicia.expects(:post).with do |request_url, options|
      doc = Nokogiri::XML(options[:body].sub("labelRequestXML=", ""))
      !doc.css("LabelRequest[#{key}='#{value}']").empty?
    end.returns(returns)
  end
  
  def expect_request_url(url)
    Endicia.expects(:post).with do |request_url, options|
      request_url == url
    end.returns(fake_response)
  end
  
  def assert_label_request_attributes(key, values)
    values.each do |value|
      expect_label_request_attribute(key, value)
      Endicia.get_label(key.to_sym => value)
    end
  end
  
  def with_rails_endicia_config(attrs)
    Endicia.instance_variable_set(:@defaults, nil)
    
    Endicia.stubs(:rails?).returns(true)
    Endicia.stubs(:rails_root).returns("/project/root")
    Endicia.stubs(:rails_env).returns("development")
    
    config = { "development" => attrs }
    config_path = "/project/root/config/endicia.yml"

    File.stubs(:exist?).with(config_path).returns(true)
    YAML.stubs(:load_file).with(config_path).returns(config)
    
    yield
    
    Endicia.instance_variable_set(:@defaults, nil)
  end
  
  def the_production_server_url(req_path)
    "https://LabelServer.Endicia.com/LabelService/EwsLabelService.asmx/#{req_path}"
  end
  
  # Don't call this "test_server_url" or ruby will try to run it as a test.
  def the_test_server_url(req_path)
    "https://www.envmgr.com/LabelService/EwsLabelService.asmx/#{req_path}"
  end  
end

class TestEndicia < Test::Unit::TestCase
  include TestEndiciaHelper
  
  context '.get_label' do
    should "use test server url if :Test option is YES" do
      expect_request_url(the_test_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "YES")
    end
  
    should "use production server url if :Test option is NO" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "NO")
    end
  
    should "use production server url if passed no :Test option" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label
    end
    
    should "send insurance option to endicia" do
      %w(OFF ON UspsOnline Endicia).each do |value|
        Endicia.expects(:post).with do |url, options|
          doc = Nokogiri::XML(options[:body].sub("labelRequestXML=", ""))
          !doc.css("LabelRequest > Services[InsuredMail=#{value}]").empty?
        end.returns(fake_response)
        Endicia.get_label({ :InsuredMail => value })
      end
    end
    
    should "raise if requesting insurance for jewelry to an excluded zip" do
      %w(10036 10017 94102 94108).each do |zip|
        options = { :InsuredMail => "Endicia", :ToPostalCode => zip, :Jewelry => true }
        assert_raise(Endicia::InsuranceError, /#{zip}/) { Endicia.get_label(options) }
      end
    end
    
    should "return an Endicia::Label object" do
      assert_kind_of Endicia::Label, Endicia.get_label
    end
    
    should "save the request body on the returned label object" do
      request_body = nil
      Endicia.expects(:post).with do |url, params|
        request_body = params[:body]
      end.returns(fake_response)
      
      the_label = Endicia.get_label
      assert_equal request_body, the_label.request_body
    end
  end
  
  context 'root node attributes on .get_label request' do
    setup do
      @request_url = "http://test.com"
      Endicia.stubs(:label_service_url).returns(@request_url)
    end
  
    should "pass LabelType option" do
      assert_label_request_attributes("LabelType", %w(Express CertifiedMail Priority))
    end
  
    should "set LabelType attribute to Default by default" do
      expect_label_request_attribute("LabelType", "Default")
      Endicia.get_label
    end
  
    should "pass Test option" do
      assert_label_request_attributes("Test", %w(YES NO))
    end
  
    should "pass LabelSize option" do
      assert_label_request_attributes("LabelSize", %w(4x6 6x4 7x3))
    end
  
    should "pass ImageFormat option" do
      assert_label_request_attributes("ImageFormat", %w(PNG GIFT PDF))
    end
  end
  
  context 'Label' do
    setup do
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
  
    should "initialize with relevant data from an endicia api response without error" do
      assert_nothing_raised { Endicia::Label.new(@response) }
    end
    
    should "include response body" do
      @response.stubs(:body).returns("the response body")
      the_label = Endicia::Label.new(@response)
      assert_equal "the response body", the_label.response_body
    end
    
    should "strip image data from #response_body" do
      @response.stubs(:body).returns("<data><one>two</one><Base64LabelImage>binary data</Base64LabelImage></data>")
      the_label = Endicia::Label.new(@response)
      assert_equal "<data><one>two</one><Base64LabelImage>[data]</Base64LabelImage></data>", the_label.response_body
    end
  end
  
  context 'defaults in rails' do
    should "load from config/endicia.yml" do
      attrs = {
        :AccountID   => 123,
        :RequesterID => "abc",
        :PassPhrase  => "123",
      }
    
      with_rails_endicia_config(attrs) do
        assert_equal attrs, Endicia.defaults
      end
    end
  
    should "support root node request attributes" do
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
    should 'make a ChangePassPhraseRequest call to the Endicia API' do
      Endicia.stubs(:label_service_url).returns("http://example.com/api")
      Time.any_instance.stubs(:to_f).returns("timestamp")
      
      Endicia.expects(:post).with do |request_url, options|
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
      end.returns(fake_response)
      
      Endicia.change_pass_phrase("newPassPhrase", {
        :PassPhrase => "oldPassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end
    
    should 'use credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "old_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.expects(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/changePassPhraseRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.ChangePassPhraseRequest &&
            doc.ChangePassPhraseRequest.RequesterID.content == "efgh" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.PassPhrase.content == "old_phrase"
          end
        end.returns(fake_response)
        
        Endicia.change_pass_phrase("new")
      end
    end
    
    should 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new", { :Test => "YES" })
    end
    
    should 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new")
    end
      
    should 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("ChangePassPhraseXML"))
        Endicia.change_pass_phrase("new")
      end
    end
    
    should "include response body in return hash" do
      response = stub_everything("response", :body => "the response body")
      Endicia.stubs(:post).returns(response)
      result = Endicia.change_pass_phrase("new")
      assert_equal "the response body", result[:response_body]
    end    
    
    context 'when successful' do
      setup do
        Endicia.stubs(:post).returns(fake_response({
          "ChangePassPhraseRequestResponse" => { "Status" => "0" }
        }))
      end
      
      should 'return hash with :success => true' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
    end
    
    context 'when not successful' do
      setup do
        Endicia.stubs(:post).returns(fake_response({
          "ChangePassPhraseRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        }))
      end
  
      should 'return hash with :success => false' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'return hash with an :error_message' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert_equal "the error message", result[:error_message]
      end
    end
  end

  context '.buy_postage(amount)' do
    should 'make a BuyPostage call to the Endicia API' do
      Endicia.stubs(:label_service_url).returns("http://example.com/api")
      Time.any_instance.stubs(:to_f).returns("timestamp")
      
      Endicia.expects(:post).with do |request_url, options|
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
      end.returns(fake_response)
      
      Endicia.buy_postage("125.99", {
        :PassPhrase => "PassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end
    
    should 'use credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.expects(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/recreditRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.RecreditRequest &&
            doc.RecreditRequest.RequesterID.content == "efgh" &&
            doc.RecreditRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.RecreditRequest.CertifiedIntermediary.PassPhrase.content == "my_phrase"
          end
        end.returns(fake_response)
        
        Endicia.buy_postage("100")
      end
    end
    
    should 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("BuyPostageXML"))
      Endicia.buy_postage("100", { :Test => "YES" })
    end
    
    should 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("BuyPostageXML"))
      Endicia.buy_postage("100")
    end
      
    should 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("BuyPostageXML"))
        Endicia.buy_postage("100")
      end
    end
    
    should "include response body in return hash" do
      response = stub_everything("response", :body => "the response body")
      Endicia.stubs(:post).returns(response)
      result = Endicia.buy_postage("100")
      assert_equal "the response body", result[:response_body]
    end
    
    context 'when successful' do
      setup do
        Endicia.stubs(:post).returns(fake_response({
          "RecreditRequestResponse" => { "Status" => "0" }
        }))
      end
      
      should 'return hash with :success => true' do
        result = Endicia.buy_postage("100")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
    end
    
    context 'when not successful' do
      setup do
        Endicia.stubs(:post).returns(fake_response({
          "RecreditRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        }))
      end
  
      should 'return hash with :success => false' do
        result = Endicia.buy_postage("100")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'return hash with an :error_message' do
        result = Endicia.buy_postage("100")
        assert_equal "the error message", result[:error_message]
      end
    end
  end
  
  context '.status_request(tracking_number, options)' do
    should 'make a StatusRequest call to the Endicia API' do
      Endicia.expects(:get).with do |els_service_url|
        regex = /http.+&method=StatusRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.StatusRequest &&
          doc.StatusRequest.AccountID.content == "123456" &&
          doc.StatusRequest.PassPhrase.content == "PassPhrase" &&
          doc.StatusRequest.Test.content == "YES" &&
          doc.StatusRequest.StatusList.PICNumber.content == "the tracking number"
        end
      end.returns(fake_response)
      
      Endicia.status_request("the tracking number", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end
    
    should 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }
      
      with_rails_endicia_config(attrs) do
        Endicia.expects(:get).with do |els_service_url|
          regex = /http.+&method=StatusRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.StatusRequest.Test.content == "YES" &&
            doc.StatusRequest.AccountID.content == "456789" &&
            doc.StatusRequest.PassPhrase.content == "my_phrase"
          end
        end.returns(fake_response)
        Endicia.status_request("the tracking number")
      end
    end
    
    should "include response body in return hash" do
      response = stub_everything("response", :body => "the response body")
      Endicia.stubs(:get).returns(response)
      result = Endicia.status_request("the tracking number")
      assert_equal "the response body", result[:response_body]
    end
    
    context 'when successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "StatusResponse" => {
            "ErrorMsg" => nil,
            "StatusList" => {
              "PICNumber" => %Q{
                abc123
                <Status>the status message</Status>
                <StatusCode>A</StatusCode>
              }
            }
          }
        }))
      end
      
      should 'include :success => true in returned hash' do
        result = Endicia.status_request("the tracking number")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
      
      should 'include status message in returned hash' do
        result = Endicia.status_request("the tracking number")
        assert_equal "the status message", result[:status]
      end
    end
    
    context 'when not successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "StatusResponse" => {
            "ErrorMsg" => "I played your man and he died."
          }
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.status_request("the tracking number")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include error message in the returned hash' do
        result = Endicia.status_request("the tracking number")
        assert_equal "I played your man and he died.", result[:error_message]
      end
    end
    
    context 'when tracking code is not found' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "StatusResponse" => {
            "ErrorMsg" => nil,
            "StatusList" => {
              "PICNumber" => %Q{
                abc123
                <Status>not found</Status>
                <StatusCode>-1</StatusCode>
              }
            }
          }
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.status_request("the tracking number")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include status message in returned hash' do
        result = Endicia.status_request("the tracking number")
        assert_equal "not found", result[:status]
      end
    end
  end

  context '.refund_request(tracking_number, options)' do
    should 'make a RefundRequest call to the Endicia API' do
      Endicia.expects(:get).with do |els_service_url|
        regex = /http.+&method=RefundRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.RefundRequest &&
          doc.RefundRequest.AccountID.content == "123456" &&
          doc.RefundRequest.PassPhrase.content == "PassPhrase" &&
          doc.RefundRequest.Test.content == "YES" &&
          doc.RefundRequest.RefundList.PICNumber.content == "the tracking number"
        end
      end.returns(fake_response)
      
      Endicia.refund_request("the tracking number", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end
    
    should 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }
      
      with_rails_endicia_config(attrs) do
        Endicia.expects(:get).with do |els_service_url|
          regex = /http.+&method=RefundRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.RefundRequest.Test.content == "YES" &&
            doc.RefundRequest.AccountID.content == "456789" &&
            doc.RefundRequest.PassPhrase.content == "my_phrase"
          end
        end.returns(fake_response)
        Endicia.refund_request("the tracking number")
      end
    end
    
    should "include response body in return hash" do
      response = stub_everything("response", :body => "the response body")
      Endicia.stubs(:get).returns(response)
      result = Endicia.refund_request("the tracking number")
      assert_equal "the response body", result[:response_body]
    end
    
    context 'when successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
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
        }))
      end
    
      should 'include :success => true in returned hash' do
        result = Endicia.refund_request("the tracking number")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end

      should 'include error_message in response' do
        result = Endicia.refund_request("the tracking number")
        assert result[:error_message] == 'Approved - Less than 10 days.'
      end

      should 'include form_number in response' do
        result = Endicia.refund_request("the tracking number")
        assert result[:form_number] == 567890
      end
    end

    context 'when login not successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "RefundResponse" => {
            "ErrorMsg" => "I played your man and he died."
          }
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include error message in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        assert_equal "I played your man and he died.", result[:error_message]
      end
    end

    context 'when refund not successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
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
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include error message in the returned hash' do
        result = Endicia.refund_request("the tracking number")
        assert_equal "Denied - Must be within 10 days.", result[:error_message]
      end
    end
  end

  context '.carrier_pickup_request(tacking_number, package_location, options)' do
    should 'make a CarrierPickupRequest call to the Endicia API' do
      Endicia.expects(:get).with do |els_service_url|
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
      end.returns(fake_response)
      
      Endicia.carrier_pickup_request("the tracking number", "sd", {
        :AccountID => "123456",
        :PassPhrase => "PassPhrase",
        :Test => "YES"
      })
    end
    
    should 'accept custom pickup address' do
      Endicia.expects(:get).with do |els_service_url|
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
      end.returns(fake_response)
      
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
    
    should 'accept custom pickup location' do
      Endicia.expects(:get).with do |els_service_url|
        regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
        els_service_url.match(regex) do |match|
          doc = Nokogiri::Slop(URI.decode(match[1]))
          doc.CarrierPickupRequest.PackageLocation.content == "ot" &&
          doc.CarrierPickupRequest.SpecialInstructions.content == "the special instructions"
        end
      end.returns(fake_response)
      
      Endicia.carrier_pickup_request("the tracking number", "ot", {
        :SpecialInstructions => "the special instructions"
      })
    end
    
    should 'use options from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :AccountID => "456789",
        :Test => "YES"
      }
      
      with_rails_endicia_config(attrs) do
        Endicia.expects(:get).with do |els_service_url|
          regex = /http.+&method=CarrierPickupRequest&XMLInput=(.+)/
          els_service_url.match(regex) do |match|
            doc = Nokogiri::Slop(URI.decode(match[1]))
            doc.CarrierPickupRequest.Test.content == "YES" &&
            doc.CarrierPickupRequest.AccountID.content == "456789" &&
            doc.CarrierPickupRequest.PassPhrase.content == "my_phrase"
          end
        end.returns(fake_response)
        Endicia.carrier_pickup_request("the tracking number", "sd")
      end
    end
    
    should "include response body in return hash" do
      response = stub_everything("response", :body => "the response body")
      Endicia.stubs(:get).returns(response)
      result = Endicia.carrier_pickup_request("the tracking number", "sd")
      assert_equal "the response body", result[:response_body]
    end
    
    context 'when successful' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "CarrierPickupRequestResponse" => {
            "Response" => {
              "DayOfWeek" => "Monday",
              "Date" => "11/11/2011",
              "CarrierRoute" => "C",
              "ConfirmationNumber" => "abc123"
            }
          }
        }))
      end
      
      should 'include :success => true in returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
      
      should 'include pickup information in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert_equal "Monday", result[:day_of_week]
        assert_equal "11/11/2011", result[:date]
        assert_equal "C", result[:carrier_route]
        assert_equal "abc123", result[:confirmation_number]
      end
    end
    
    context 'when there is an error message' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "CarrierPickupRequestResponse" => {
            "ErrorMsg" => "your ego is out of control"
          }
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include error message in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert_equal "your ego is out of control", result[:error_message]
      end
    end

    context 'when there is an error code' do
      setup do
        Endicia.stubs(:get).returns(fake_response({
          "CarrierPickupRequestResponse" => {
            "Response" => {
              "Error" => {
                "Number" => "123",
                "Description" => "OverThere is an invalid package location"
              }
            }
          }
        }))
      end
      
      should 'include :success => false in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'include error code in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert_equal "123", result[:error_code]
      end

      should 'include error message in the returned hash' do
        result = Endicia.carrier_pickup_request("the tracking number", "sd")
        assert_equal "OverThere is an invalid package location", result[:error_description]
      end
    end
  end
end
