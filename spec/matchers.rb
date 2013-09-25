  def fake_response(hash = {}, body = "")
    hash.stub(:body) {body}
    hash
  end

  def expect_label_request_attribute(key, value, returns = fake_response)
    Endicia.should_receive(:post).with do |request_url, options|
      doc = Nokogiri::XML(options[:body].sub("labelRequestXML=", ""))
      !doc.css("LabelRequest[#{key}='#{value}']").empty?
    end.and_return(returns)
  end

  def expect_label_request_body_with(&block)
    Endicia.should_receive(:post).with do |url, options|
      doc = Nokogiri::XML(options[:body].sub("labelRequestXML=", ""))
      block.call(doc)
    end.and_return(fake_response)
  end

  def expect_request_url(url)
    Endicia.should_receive(:post).with do |request_url, options|
      request_url == url
    end.and_return(fake_response)
  end

  def assert_label_request_attributes(key, values)
    values.each do |value|
      expect_label_request_attribute(key, value)
      Endicia.get_label(key.to_sym => value)
    end
  end

  def with_rails_endicia_config(attrs)
    Endicia.instance_variable_set(:@defaults, nil)

    Endicia.stub(:rails?) {true}
    Endicia.stub(:rails_root) {"/project/root"}
    Endicia.stub(:rails_env) {"development"}

    config = { "development" => attrs }
    config_path = "/project/root/config/endicia.yml"

    File.stub(:exist?).with(config_path) {true}
    YAML.stub(:load_file).with(config_path) {config}

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
