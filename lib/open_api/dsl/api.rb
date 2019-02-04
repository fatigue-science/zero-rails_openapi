# frozen_string_literal: true

require 'open_api/dsl/common_dsl'

module OpenApi
  module DSL
    class Api < Hash
      include DSL::CommonDSL
      include DSL::Helpers

      attr_accessor :action_path, :dry_skip, :dry_only, :dry_blocks, :dryed, :param_order

      def initialize(action_path = '', summary: nil, tags: [ ], id: nil)
        self.action_path = action_path
        self.dry_blocks  = [ ]
        self.merge!(summary: summary, operationId: id, tags: tags, description: '', parameters: [ ],
                    requestBody: '', responses: { }, callbacks: { }, links: { }, security: [ ], servers: [ ])
      end

      def this_api_is_invalid!(*)
        self[:deprecated] = true
      end

      alias this_api_is_expired!      this_api_is_invalid!
      alias this_api_is_unused!       this_api_is_invalid!
      alias this_api_is_under_repair! this_api_is_invalid!

      def desc desc
        self[:description] = desc
      end

      alias description desc

      def dry only: nil, skip: nil, none: false
        return if dry_blocks.blank? || dryed
        self.dry_skip = skip && Array(skip)
        self.dry_only = none ? [:none] : only && Array(only)
        dry_blocks.each { |blk| instance_eval(&blk) }
        self.dry_skip = self.dry_only = nil
        self.dryed = true
      end

      def param param_type, name, type, required, schema_info = { }
        return if dry_skip&.include?(name) || dry_only&.exclude?(name)

        param_obj = ParamObj.new(name, param_type, type, required, schema_info)
        # The definition of the same name parameter will be overwritten
        fill_in_parameters(param_obj)
      end

      alias parameter param

      %i[ header header! path path! query query! cookie cookie! ].each do |param_type|
        define_method param_type do |name, type = nil, **schema_info|
          schema = process_schema_info(type, schema_info)
          return Tip.param_no_type(name) if schema[:illegal?]
          param param_type, name, schema[:type], (param_type['!'] ? :req : :opt),
                schema[:combined] || schema[:info]
        end

        # For supporting this: (just like `form '', data: { }` usage)
        #   in_query(
        #     :search_type => String,
        #         :export! => { type: Boolean }
        #   )
        define_method "in_#{param_type}" do |params|
          params.each_pair do |param_name, schema|
            param param_type, param_name.to_sym, nil, (param_type['!'] || param_name['!'] ? :req : :opt), schema
          end
        end
      end

      def param_ref component_key, *keys
        self[:parameters] += [component_key, *keys].map { |key| RefObj.new(:parameter, key) }
      end

      # options: `exp_by` and `examples`
      def request_body required, media_type, data: { }, **options
        desc = options.delete(:desc) || ''
        self[:requestBody] = RequestBodyObj.new(required, desc) unless self[:requestBody].is_a?(RequestBodyObj)
        self[:requestBody].add_or_fusion(media_type, { data: data , **options })
      end

      # [ body body! ]
      def _request_body_agent media_type, data: { }, **options
        request_body @necessity, media_type, data: data, **options
      end

      def body_ref component_key
        self[:requestBody] = RefObj.new(:requestBody, component_key)
      end

      def form data:, **options
        body :form, data: data, **options
      end

      def form! data:, **options
        body! :form, data: data, **options
      end

      def data name, type = nil, schema_info = { }
        schema_info[:type] = type if type.present?
        form data: { name => schema_info }
      end

      def file media_type, data: { type: File }, **options
        body media_type, data: data, **options
      end

      def file! media_type, data: { type: File }, **options
        body! media_type, data: data, **options
      end

      def response_ref code_compkey_hash
        code_compkey_hash.each { |code, component_key| self[:responses][code] = RefObj.new(:response, component_key) }
      end

      def security_require scheme_name, scopes: [ ]
        self[:security] << { scheme_name => scopes }
      end

      alias security  security_require
      alias auth      security_require
      alias need_auth security_require

      def callback event_name, http_method, callback_url, &block
        self[:callbacks].deep_merge! CallbackObj.new(event_name, http_method, callback_url, &block).process
      end

      def server url, desc: ''
        self[:servers] << { url: url, description: desc }
      end

      def param_examples exp_by = :all, examples_hash
        exp_by = self[:parameters].map(&:name) if exp_by == :all
        self[:examples] = ExampleObj.new(examples_hash, exp_by, multiple: true).process
      end

      alias examples param_examples

      def run_dsl(dry: false, &block)
        instance_exec(&block) if block_given?
        dry() if dry
        process_objs
      end

      def process_objs
        self[:parameters].map!(&:process)
        self[:requestBody] = self[:requestBody].try(:process)
        self[:responses].each { |code, response| self[:responses][code] = response.process }
        self[:responses] = self[:responses].sort.to_h
        self.delete_if { |_, v| v.blank? }
      end
    end
  end
end
