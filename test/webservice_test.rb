require 'helper'

class WebServiceTest < ActionDispatch::IntegrationTest
  class TestController < ActionController::Base
    def assign_parameters
      if params[:full]
        render plain: dump_params_keys
      else
        render plain: (params.keys - ['controller', 'action']).sort.join(", ")
      end
    end

    def dump_params_keys(hash = params)
      hash.keys.sort.inject("") do |s, k|
        value = hash[k]

        if value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
          value = "(#{dump_params_keys(value)})"
        else
          value = ""
        end

        s << ", " unless s.empty?
        s << "#{k}#{value}"
      end
    end
  end

  def setup
    @controller = TestController.new
    @integration_session = nil
  end

  def test_check_parameters
    with_test_route_set do
      get "/"
      assert_equal '', @controller.response.body
    end
  end

  def test_post_xml
    with_test_route_set do
      post "/", params: '<entry attributed="true"><summary>content...</summary></entry>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert_equal 'entry', @controller.response.body
      assert @controller.params.has_key?(:entry)
      assert_equal 'content...', @controller.params["entry"]['summary']
      assert_equal 'true', @controller.params["entry"]['attributed']
    end
  end

  def test_put_xml
    with_test_route_set do
      put "/", params: '<entry attributed="true"><summary>content...</summary></entry>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert_equal 'entry', @controller.response.body
      assert @controller.params.has_key?(:entry)
      assert_equal 'content...', @controller.params["entry"]['summary']
      assert_equal 'true', @controller.params["entry"]['attributed']
    end
  end

  def test_put_xml_using_a_type_node
    with_test_route_set do
      put "/", params: '<type attributed="true"><summary>content...</summary></type>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert_equal 'type', @controller.response.body
      assert @controller.params.has_key?(:type)
      assert_equal 'content...', @controller.params["type"]['summary']
      assert_equal 'true', @controller.params["type"]['attributed']
    end
  end

  def test_put_xml_using_a_type_node_and_attribute
    with_test_route_set do
      put "/", params: '<type attributed="true"><summary type="boolean">false</summary></type>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert_equal 'type', @controller.response.body
      assert @controller.params.has_key?(:type)
      assert_equal false, @controller.params["type"]['summary']
      assert_equal 'true', @controller.params["type"]['attributed']
    end
  end

  def test_post_xml_using_a_type_node
    with_test_route_set do
      post "/", params: '<font attributed="true"><type>arial</type></font>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert_equal 'font', @controller.response.body
      assert @controller.params.has_key?(:font)
      assert_equal 'arial', @controller.params['font']['type']
      assert_equal 'true', @controller.params["font"]['attributed']
    end
  end

  def test_post_xml_using_a_root_node_named_type
    with_test_route_set do
      post "/", params: '<type type="integer">33</type>',
        headers: {'CONTENT_TYPE' => 'application/xml'}

      assert @controller.params.has_key?(:type)
      assert_equal 33, @controller.params['type']
    end
  end

  def test_post_xml_using_an_attributted_node_named_type
    with_test_route_set do
      with_params_parsers Mime[:xml] => Proc.new { |data| Hash.from_xml(data)['request'].with_indifferent_access } do
        post "/", params: '<request><type type="string">Arial,12</type><z>3</z></request>',
          headers: {'CONTENT_TYPE' => 'application/xml'}

        assert_equal 'type, z', @controller.response.body
        assert @controller.params.has_key?(:type)
        assert_equal 'Arial,12', @controller.params['type'], @controller.params.inspect
        assert_equal '3', @controller.params['z'], @controller.params.inspect
      end
    end
  end

  def test_post_xml_using_a_disallowed_type_attribute
    $stderr = StringIO.new
    with_test_route_set do
      post '/', params: '<foo type="symbol">value</foo>', headers: {'CONTENT_TYPE' => 'application/xml'}
      assert_response 400

      post '/', params: '<foo type="yaml">value</foo>', headers: {'CONTENT_TYPE' => 'application/xml'}
      assert_response 400
    end
  ensure
    $stderr = STDERR
  end

  def test_register_and_use_xml_simple
    with_test_route_set do
      with_params_parsers Mime[:xml] => Proc.new { |data| Hash.from_xml(data)['request'].with_indifferent_access } do
        post "/", params: '<request><summary>content...</summary><title>SimpleXml</title></request>',
          headers: {'CONTENT_TYPE' => 'application/xml'}

        assert_equal 'summary, title', @controller.response.body
        assert @controller.params.has_key?(:summary)
        assert @controller.params.has_key?(:title)
        assert_equal 'content...', @controller.params["summary"]
        assert_equal 'SimpleXml', @controller.params["title"]
      end
    end
  end

  def test_use_xml_ximple_with_empty_request
    with_test_route_set do
      assert_nothing_raised { post "/", params: "", headers: {'CONTENT_TYPE' => 'application/xml'} }
      assert_equal '', @controller.response.body
    end
  end

  def test_dasherized_keys_as_xml
    with_test_route_set do
      post "/?full=1", params: "<first-key>\n<sub-key>...</sub-key>\n</first-key>",
        headers: {'CONTENT_TYPE' => 'application/xml'}
      assert_equal 'action, controller, first_key(sub_key), full', @controller.response.body
      assert_equal "...", @controller.params[:first_key][:sub_key]
    end
  end

  def test_typecast_as_xml
    with_test_route_set do
      xml = <<-XML
        <data>
          <a type="integer">15</a>
          <b type="boolean">false</b>
          <c type="boolean">true</c>
          <d type="date">2005-03-17</d>
          <e type="datetime">2005-03-17T21:41:07Z</e>
          <f>unparsed</f>
          <g type="integer">1</g>
          <g>hello</g>
          <g type="date">1974-07-25</g>
        </data>
      XML
      post "/", params: xml, headers: {'CONTENT_TYPE' => 'application/xml'}

      params = @controller.params
      assert_equal 15, params[:data][:a]
      assert_equal false, params[:data][:b]
      assert_equal true, params[:data][:c]
      assert_equal Date.new(2005,3,17), params[:data][:d]
      assert_equal Time.utc(2005,3,17,21,41,7), params[:data][:e]
      assert_equal "unparsed", params[:data][:f]
      assert_equal [1, "hello", Date.new(1974,7,25)], params[:data][:g]
    end
  end

  def test_entities_unescaped_as_xml_simple
    with_test_route_set do
      xml = <<-XML
        <data>&lt;foo &quot;bar&apos;s&quot; &amp; friends&gt;</data>
      XML
      post "/", params: xml, headers: {'CONTENT_TYPE' => 'application/xml'}
      assert_equal %(<foo "bar's" & friends>), @controller.params[:data]
    end
  end

  private
    def with_params_parsers(parsers = {})
      old_session = @integration_session
      @app = ActionDispatch::ParamsParser.new(app.routes, parsers)
      reset!
      yield
    ensure
      @integration_session = old_session
    end

    def with_test_route_set
      with_routing do |set|
        set.draw do
          match '/', :to => 'web_service_test/test#assign_parameters', :via => :all
        end
        yield
      end
    end
end
