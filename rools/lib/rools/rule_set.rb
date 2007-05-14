require 'rools/errors'
require 'rools/rule'
require 'rools/base'
require 'rools/facts'
require 'rools/csv_table'

require 'rexml/document'

module Rools
  class RuleSet < Base
    attr_reader :num_executed, :num_evaluated, :facts
    
    PASS = :pass
    FAIL = :fail
    
  
    # You can pass a set of Rools::Rules with a block parameter,
    # or you can pass a file-path to evaluate.
    def initialize(file = nil, &b)
      
      @rules = {}
      @facts = {}
      @dependencies = {}
      
      if block_given?
        instance_eval(&b)
      else
        # loading a file, check extension
        name,ext = file.split(".")
        logger.debug("loading ext: #{ext}") if logger
        case ext
          when 'csv'
            load_csv( file )
            
          when 'xml'
            load_xml( file )
            
          when 'rb'
            load_rb( file )
              
          when 'rules'  # for backwards compatibility
            load_rb(file)
            
          else
            raise "invalid file extension: #{ext}"
        end
       end
    end		
    
    #
    # Loads decision table
    #
    def load_csv( file )
      csv = CsvTable.new( file )
      logger.debug "csv rules: #{csv.rules}" if logger
      instance_eval(csv.rules)
    end
    
    #
    # XML File format loading
    #
    def load_xml( fileName )
      file = File.new( fileName )
      doc = REXML::Document.new file
      doc.elements.each( "rule-set") { |rs| 
        facts = rs.elements.each( "facts") { |f| 
          facts( f.attributes["name"] ) do f.text.strip end
        }
        
        rules = rs.elements.each( "rule") { |rule_node|
           rule_name  = rule_node.attributes["name"]
           priority   = rule_node.attributes["priority"]
           
           rule       = Rule.new(self, rule_name, priority, nil)
           
           parameters = rule_node.elements.each("parameter") { |param|
              rule.parameter do eval(param.text.strip) end
           } 
           
           conditions = rule_node.elements.each("condition") { |cond|
              rule.condition do eval(cond.text.strip) end
           } 
 
           consequences = rule_node.elements.each("consequence") { |cons|
              rule.consequence do eval(cons.text.strip) end
           } 
           
           @rules[rule_name] = rule
        }
      }
    end
    
    #
    # Ruby File format
    #
    def load_rb( file )
      instance_eval(File::open(file).read)
    end
    
    def get_facts
      @facts
    end
 
    # rule creates a Rools::Rule. Make sure to use a descriptive name or symbol.
    # For the purposes of extending Rules, all names are converted to
    # strings and downcased.
    # ==Example
    #   rule 'ruby is the best' do
    #     condition { language.name.downcase == 'ruby' }
    #     consequence { "#{language.name} is the best!" }
    #   end
    def rule(name, priority=0, &b)
      name.to_s.downcase!
      @rules[name] = Rule.new(self, name, priority, b)
    end
    
    # facts can be created in a similar manner to rules
    # all names are converted to strings and downcased.
    # Facts name is equivalent to a Class Name
    # ==Example
    # require 'rools'
	#
	# rules = Rools::RuleSet.new do
	#	
	#	facts 'Countries' do
	#		["China", "USSR", "France", "Great Britain", "USA"]
	#	end
	#	
	#	rule 'Is it on Security Council?' do
	#	  parameter String
	#		condition { countries.include?(string) }
	#		consequence { puts "Yes, #{string} is in the country list"}
	#	end
	# end
    #
	# rules.assert 'France'
    #
    def facts(name, &b)
      name.to_s.downcase!
      @facts[name] = Facts.new(self, name, b)
    end
    
    # a single fact can be an single object of a particular class type
    # 
    def fact( obj )
    begin
      # check if facts already exist for that class
      cls = obj.class.to_s.downcase
      if @facts.key? cls
        logger.debug( "adding to facts: #{cls}") if logger
        @facts[cls].fact_value << obj
      else
        logger.debug( "creating facts: #{cls}") if logger
        arr = Array.new
        arr << obj
        proc = Proc.new { arr }
        @facts[cls] = Facts.new(self, cls, proc ) 
      end
    rescue Exception=> e
      puts e
    end
    end
    
    # Use in conjunction with Rools::RuleSet#with to create a Rools::Rule dependent on
    # another. Dependencies are created through names (converted to
    # strings and downcased), so lax naming can get you into trouble with
    # creating dependencies or overwriting rules you didn't mean to.
    def extend(name, &b)
      name.to_s.downcase!
      @extend_rule_name = name
      instance_eval(&b) if block_given?
      return self
    end
    
    # Used in conjunction with Rools::RuleSet#extend to create a dependent Rools::Rule
    # ==Example
    #   extend('ruby is the best').with('ruby rules the world') do
    #     condition { language.age > 15 }
    #     consequence { "In the year 2008 Ruby conquered the known universe" }
    #   end
    def with(name, &b)
      name.to_s.downcase!
       (@dependencies[@extend_rule_name] ||= []) << Rule.new(self, name, b)
    end
    
    # Stops the current assertion. Does not indicate failure.
    def stop(message = nil)
      @assert = false
    end
    
    # Stops the current assertion and change status to :fail
    def fail(message = nil)
      @status = FAIL
      @assert = false
    end
    
 
    
    # Used to create a working-set of rules for an object, and evaluate it
    # against them. Returns a status, simply PASS or FAIL
    def assert_1(obj)
      @status = PASS
      @assert = true
      @num_executed = 0;
      @num_evaluated = 0;
      
      # create a working-set of all parameter-matching, non-dependent rules
      available_rules = @rules.values.select { |rule| rule.parameters_match?(obj) }
      
      available_rules = available_rules.sort do  |r1, r2| 
        r2.priority <=> r1.priority 
      end
      
      begin
        
        # loop through the available_rules, evaluating each one,
        # until there are no more matching rules available
        begin # loop
          
          # the loop condition is reset to break by default after every iteration
          matches = false
          #logger.debug("available rules: #{available_rules.size.to_s}") if logger
          available_rules.each do |rule|
            # RuleCheckErrors are caught and swallowed and the rule that
            # raised the error is removed from the working-set.
            logger.debug("evaluating: #{rule}") if logger
            begin
              @num_evaluated += 1
              if rule.conditions_match?(obj)
                logger.debug("rule #{rule} matched") if logger
                matches = true
                
                # remove the rule from the working-set so it's not re-evaluated
                available_rules.delete(rule)
                
                # find all parameter-matching dependencies of this rule and
                # add them to the working-set.
                if @dependencies.has_key?(rule.name)
                  available_rules += @dependencies[rule.name].select do |dependency|
                    dependency.parameters_match?(obj)
                  end
                end
                
                # execute this rule
                logger.debug("executing rule #{rule}") if logger
                rule.call(obj)
                @num_executed += 1
                
                # break the current iteration and start back from the first rule defined.
                break
              end # if rule.conditions_match?(obj)
              
            rescue RuleCheckError => e
              # log da error or sumpin
              available_rules.delete(e.rule)
              @status = fail
            end # begin/rescue
            
          end # available_rules.each
          
        end while(matches && @assert)
        
      rescue RuleConsequenceError => rce
        # RuleConsequenceErrors are allowed to break out of the current assertion,
        # then the inner error is bubbled-up to the asserting code.
        @status = fail
        raise rce.inner_error
      end
      
      @assert = false
      
      return @status
    end # def assert
    
    # turn passed object into facts and call evaluate
    def assert( *objs )
      objs.each { |obj| 
        fact(obj)
      }
      return evaluate()
    end
    
    # get all relevant rules for all specified facts
    def get_relevant_rules
      @relevant_rules = Array.new
      @facts.each { |k,f| 
        @rules.values.select { |rule| 
          if rule.parameters_match?(f.value) && !@relevant_rules.include?( rule)
            @relevant_rules << rule 
            logger.debug "#{rule} is relevant" if logger
          end 
        } 
      }
      
      # sort array in rule priority order
      @relevant_rules = @relevant_rules.sort do  |r1, r2| 
        r2.priority <=> r1.priority 
      end
    end
    
    # evaluate all relevant rules for specified facts
    def evaluate
      @status = PASS
      @assert = true
      @num_executed = 0;
      @num_evaluated = 0;
      
      get_relevant_rules()

      begin #rescue
        
        # loop through the available_rules, evaluating each one,
        # until there are no more matching rules available
        begin # loop
          
          # the loop condition is reset to break by default after every iteration
          matches = false
          obj     = nil #deprecated
 
          #logger.debug("available rules: #{available_rules.size.to_s}") if logger
          @relevant_rules.each do |rule|
            # RuleCheckErrors are caught and swallowed and the rule that
            # raised the error is removed from the working-set.
            logger.debug("evaluating: #{rule}") if logger
            begin
              @num_evaluated += 1
              if rule.conditions_match?(obj)
                logger.debug("rule #{rule} matched") if logger
                matches = true
                
                # remove the rule from the working-set so it's not re-evaluated
                @relevant_rules.delete(rule)
                
                # find all parameter-matching dependencies of this rule and
                # add them to the working-set.
                #if @dependencies.has_key?(rule.name)
                #  @relevant_rules += @dependencies[rule.name].select do |dependency|
                #    dependency.parameters_match?(obj)
                #  end
                #end
                
                # execute this rule
                logger.debug("executing rule #{rule}") if logger
                rule.call(obj)
                @num_executed += 1
                
                # break the current iteration and start back from the first rule defined.
                break
              end # if rule.conditions_match?(obj)
              
            rescue RuleCheckError => e
              # log da error or sumpin
              @relevant_rules.delete(e.rule)
              @status = fail
            end # begin/rescue
            
          end # available_rules.each
          
        end while(matches && @assert)
        
      rescue RuleConsequenceError => rce
        # RuleConsequenceErrors are allowed to break out of the current assertion,
        # then the inner error is bubbled-up to the asserting code.
        @status = fail
        raise rce.inner_error
      end
      
      @assert = false
      
      return @status
    end
    
  end # class RuleSet
end # module Rools