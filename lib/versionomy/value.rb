# -----------------------------------------------------------------------------
# 
# Versionomy value
# 
# -----------------------------------------------------------------------------
# Copyright 2008-2009 Daniel Azuma
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# -----------------------------------------------------------------------------
;


require 'yaml'


module Versionomy
  
  
  # === Version number value
  # 
  # A version number value is an ordered list of values, corresponding to an
  # ordered list of fields defined by a schema. For example, if the schema
  # is a simple one of the form "major.minor.tiny", then the the version
  # number "1.4.2" would have the values <tt>[1, 4, 2]</tt> in that order,
  # corresponding to the fields <tt>[:major, :minor, :tiny]</tt>.
  # 
  # Version number values are comparable with other values that have an
  # equivalent schema.
  
  class Value
    
    
    # Create a value, given a hash or array of values, and a format. Both
    # these parameters are required.
    # 
    # The values should either be a hash of field names and values, or an
    # array of values that will be interpreted in field order.
    # 
    # You can also optionally provide default unparsing parameters for the
    # value.
    
    def initialize(values_, format_, unparse_params_=nil)
      unless values_.kind_of?(::Hash) || values_.kind_of?(::Array)
        raise ::ArgumentError, "Expected hash or array but got #{values_.class}"
      end
      @_format = format_
      @_unparse_params = unparse_params_
      @_field_path = []
      @_values = {}
      values_ = _canonicalize_values_hash(values_) if values_.kind_of?(::Hash)
      field_ = @_format.schema.root_field
      while field_
        value_ = values_.kind_of?(::Hash) ? values_[field_.name] : values_.shift
        value_ = value_ ? field_.canonicalize_value(value_) : field_.default_value
        @_field_path << field_
        @_values[field_.name] = value_
        field_ = field_.child(value_)
      end
      modules_ = @_format.schema.modules
      extend(*modules_) if modules_.size > 0
    end
    
    
    def inspect  # :nodoc:
      begin
        str_ = unparse
        "#<#{self.class}:0x#{object_id.to_s(16)} #{str_.inspect}>"
      rescue Errors::UnparseError
        _inspect
      end
    end
    
    def _inspect  # :nodoc:
      "#<#{self.class}:0x#{object_id.to_s(16)} " +
        @_field_path.map{ |field_| "#{field_.name}=#{@_values[field_.name].inspect}" }.join(' ')
    end
    
    
    # Returns a string representation generated by unparsing.
    # If unparsing fails, does not raise Versionomy::Errors::UnparseError,
    # but instead returns the string generated by +inspect+.
    
    def to_s
      begin
        unparse
      rescue Errors::UnparseError
        _inspect
      end
    end
    
    
    # Marshal this version number.
    
    def marshal_dump  # :nodoc:
      format_name_ = Format.canonical_name_for(@_format, true)
      unparsed_data_ = nil
      if @_format.respond_to?(:unparse_for_serialization)
        unparsed_data_ = @_format.unparse_for_serialization(self) rescue nil
      end
      unparsed_data_ ||= @_format.unparse(self) rescue nil
      data_ = [format_name_]
      case unparsed_data_
      when ::Array
        data_ << unparsed_data_[0]
        data_ << unparsed_data_[1] if unparsed_data_[1]
      when ::String
        data_ << unparsed_data_
      else
        data_ << values_array
        data_ << @_unparse_params if @_unparse_params
      end
      data_
    end
    
    
    # Unmarshal this version number.
    
    def marshal_load(data_)  # :nodoc:
      format_ = Format.get(data_[0], true)
      if data_[1].kind_of?(::String)
        val_ = format_.parse(data_[1], data_[2])
        initialize(val_.values_array, format_, val_.unparse_params)
      else
        initialize(data_[1], format_, data_[2])
      end
    end
    
    
    # YAML tags. The last one is the canonical one.
    yaml_as "tag:danielazuma.com,2009:version"
    yaml_as "tag:verse15.com,2009:version"
    
    
    # Deserialize a version number from YAML
    
    def self.yaml_new(klass_, tag_, data_)  # :nodoc:
      unless data_.kind_of?(::Hash)
        raise ::YAML::TypeError, "Invalid version format: #{val_.inspect}"
      end
      format_ = Format.get(data_['format'], true)
      value_ = data_['value']
      if value_
        format_.parse(value_, data_['parse_params'])
      else
        Value.new(format_, data_['fields'], data_['unparse_params'])
      end
    end
    
    
    # Serialize this version number to YAML format.
    
    def to_yaml(opts_={})
      data_ = marshal_dump
      ::YAML::quick_emit(nil, opts_) do |out_|
        out_.map(taguri, to_yaml_style) do |map_|
          map_.add('format', data_[0])
          if data_[1].kind_of?(::String)
            map_.add('value', data_[1])
            map_.add('parse_params', data_[2]) if data_[2]
          else
            map_.add('fields', data_[1])
            map_.add('unparse_params', data_[2]) if data_[2]
          end
        end
      end
    end
    
    
    # Unparse this version number and return a string.
    # 
    # Raises Versionomy::Errors::UnparseError if unparsing failed.
    
    def unparse(params_=nil)
      @_format.unparse(self, params_)
    end
    
    
    # Return the schema defining the structure and semantics of this
    # version number.
    
    def schema
      @_format.schema
    end
    
    
    # Return the format defining the schema and formatting/parsing of
    # this version number.
    
    def format
      @_format
    end
    
    
    # Return the unparsing parameters for this value.
    # Returns nil if this value was not created using a parser.
    
    def unparse_params
      @_unparse_params ? @_unparse_params.dup : nil
    end
    
    
    # Iterates over each field, in field order, yielding the field name and value.
    
    def each_field
      @_field_path.each do |field_|
        yield(field_, @_values[field_.name])
      end
    end
    
    
    # Iterates over each field, in field order, yielding the
    # Versionomy::Schema::Field object and value.
    
    def each_field_object  # :nodoc:
      @_field_path.each do |field_|
        yield(field_, @_values[field_.name])
      end
    end
    
    
    # Returns an array of recognized field names for this value, in field order.
    # This is the order of the fields actually present in this value, in
    # order from most to least significant.
    
    def field_names
      @_field_path.map{ |field_| field_.name }
    end
    
    
    # Returns true if this value contains the given field, which may be specified
    # as a field object, name, or index.
    
    def has_field?(field_)
      case field_
      when Schema::Field
        @_field_path.include?(field_)
      when ::Integer
        @_field_path.size > field_ && field_ >= 0
      when ::String, ::Symbol
        @_values.has_key?(@_format.schema.canonical_name(field_))
      else
        raise ::ArgumentError
      end
    end
    
    
    # Returns the value of the given field, or nil if the field is not
    # recognized. The field may be specified as a field object, field name,
    # or field index.
    
    def [](field_)
      @_values[_interpret_field(field_)]
    end
    
    
    # Returns the value as an array of field values, in field order.
    # This is the order of the fields actually present in this value, in
    # order from most to least significant.
    
    def values_array
      @_field_path.map{ |field_| @_values[field_.name] }
    end
    
    
    # Returns the value as a hash of values keyed by field name.
    
    def values_hash
      @_values.dup
    end
    
    
    # Returns a new version number created by bumping the given field. The
    # field may be specified as a field object, field name, or field index.
    # Returns self unchanged if the field was not recognized or could not
    # be modified.
    
    def bump(field_)
      name_ = _interpret_field(field_)
      return self unless name_ && @_values.include?(name_)
      values_ = []
      @_field_path.each do |fld_|
        oldval_ = @_values[fld_.name]
        if fld_.name == name_
          newval_ = fld_.bump_value(oldval_)
          return self if newval_ == oldval_
          values_ << newval_
          return Value.new(values_, @_format, @_unparse_params)
        else
          values_ << oldval_
        end
      end
      self
    end
    
    
    # Returns a new version number created by resetting the given field. The
    # field may be specified as a field object, field name, or field index.
    # Returns self unchanged if the field was not recognized or could not
    # be modified.
    
    def reset(field_)
      name_ = _interpret_field(field_)
      return self unless name_ && @_values.include?(name_)
      values_ = []
      @_field_path.each do |fld_|
        oldval_ = @_values[fld_.name]
        if fld_.name == name_
          values_ << fld_.default_value
          return Value.new(values_, @_format, @_unparse_params)
        else
          values_ << oldval_
        end
      end
      self
    end
    
    
    # Returns a new version number created by cloning this version number
    # and changing the given field values.
    # 
    # You should pass in a hash of field names to values. These are the
    # fields to modify; any other fields will be left alone, unless they
    # are implicitly changed by the modifications you are making.
    # For example, changing the :release_type on a value using the standard
    # format, may change which fields are present in the resulting value.
    # 
    # You may also pass a delta hash to modify the unparse params stored in
    # the value.
    
    def change(values_={}, unparse_params_={})
      unparse_params_ = @_unparse_params.merge(unparse_params_) if @_unparse_params
      values_ = _canonicalize_values_hash(values_)
      Value.new(@_values.merge(values_), @_format, unparse_params_)
    end
    
    
    # Attempts to convert this value to the given format, and returns the
    # resulting value.
    # 
    # Raises Versionomy::Errors::ConversionError if the value could not
    # be converted.
    
    def convert(format_, convert_params_=nil)
      if format_.kind_of?(::String) || format_.kind_of?(::Symbol)
        format_ = Format.get(format_)
      end
      return self if @_format == format_
      from_schema_ = @_format.schema
      to_schema_ = format_.schema
      if from_schema_ == to_schema_
        return Value.new(@_values, format_, convert_params_)
      end
      conversion_ = Conversion.get(from_schema_, to_schema_)
      if conversion_
        conversion_.convert_value(self, format_, convert_params_)
      else
        standard_format_ = Format.get(:standard)
        conversion1_ = Conversion.get(from_schema_, standard_format_)
        conversion2_ = Conversion.get(standard_format_, to_schema_)
        if conversion1_ && conversion2_
          value_ = conversion1_.convert_value(self, standard_format_, convert_params_)
          conversion2_.convert_value(value_, format_, convert_params_)
        else
          raise Errors::UnknownConversionError
        end
      end
    end
    
    
    def hash  # :nodoc:
      @_hash ||= @_values.hash
    end
    
    
    # Returns true if this version number is equivalent to the given number.
    # This type of equality means their schemas are compatible and their
    # field values are equal.
    # Note that this is different from the definition of <tt>==</tt>.
    
    def eql?(obj_)
      if obj_.kind_of?(::String)
        obj_ = @_format.parse(obj_) rescue nil
      end
      return false unless obj_.kind_of?(Value)
      index_ = 0
      obj_.each_field_object do |field_, value_|
        return false if field_ != @_field_path[index_] || value_ != @_values[field_.name]
        index_ += 1
      end
      true
    end
    
    
    # Returns true if this version number is value-equal to the given number.
    # This type of equality means that they are equivalent, or that it is
    # possible to convert the RHS to the LHS's format, and that they would
    # be equivalent after such a conversion has taken place.
    # Note that this is different from the definition of <tt>eql?</tt>.
    
    def ==(obj_)
      (self <=> obj_) == 0
    end
    
    
    # Compare this version number with the given version number,
    # returning 0 if the two are value-equal, a negative number if the RHS
    # is greater, or a positive number if the LHS is greater.
    # The comparison may succeed even if the two have different schemas,
    # if the RHS can be converted to the LHS's format.
    
    def <=>(obj_)
      if obj_.kind_of?(::String)
        obj_ = @_format.parse(obj_)
      end
      return nil unless obj_.kind_of?(Value)
      if obj_.schema != @_format.schema
        begin
          obj_ = obj_.convert(@_format)
        rescue
          return nil
        end
      end
      obj_.each_field_object do |field_, value_|
        val_ = field_.compare_values(@_values[field_.name], value_)
        return val_ if val_ != 0
      end
      0
    end
    
    
    # Compare this version number with the given version number.
    # The comparison may succeed even if the two have different schemas,
    # if the RHS can be converted to the LHS's format.
    
    def <(obj_)
      val_ = (self <=> obj_)
      unless val_
        raise Errors::SchemaMismatchError
      end
      val_ < 0
    end
    
    
    # Compare this version number with the given version number.
    # The comparison may succeed even if the two have different schemas,
    # if the RHS can be converted to the LHS's format.
    
    def >(obj_)
      val_ = (self <=> obj_)
      unless val_
        raise Errors::SchemaMismatchError
      end
      val_ > 0
    end
    
    
    include ::Comparable
    
    
    # Field values may be retrieved by calling them as methods.
    
    def method_missing(symbol_)
      self[symbol_] || super
    end
    
    
    private
    
    def _interpret_field(field_)   # :nodoc:
      case field_
      when Schema::Field
        @_format.schema.canonical_name(field_.name)
      when ::Integer
        field_ = @_field_path[field_]
        field_ ? field_.name : nil
      when ::String, ::Symbol
        @_format.schema.canonical_name(field_)
      end
    end
    
    
    def _canonicalize_values_hash(values_)  # :nodoc:
      schema_ = @_format.schema
      new_values_ = {}
      values_.each do |k_,v_|
        k_ = schema_.canonical_name(k_)
        new_values_[k_] = v_ if k_
      end
      new_values_
    end
    
    
  end
  
  
end
