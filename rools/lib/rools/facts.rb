require 'rools/errors'
require 'rools/default_parameter_proc'
require 'rools/base'

#
# Facts are collections or recordsets created by the user
# 
module Rools
  class Facts < Base
    attr_reader :name, :fact_value
    
    def initialize(rule_set, name, b)
      @name = name
      @fact_value = instance_eval( &b )
      #logger.debug "New Facts: #{@fact_value}" if logger
    end
    
    def value
      if @fact_value.size == 1
        @fact_value[0]
      else
        @fact_value
      end
    end
  end
end