# `singleton_class` is a macro that simulates the Singleton class used in Sup.
# Use this macro at the start of the class.  It declares the single instance
# of the class, and defines methods for accessing, deinitializing, and querying
# the existence of this instance. Use the `singleton_pre_init` and
# `singleton_post_init` macros in the class `initialize` method.  Use
# the `singleton_method` macro to define methods that must be bound
# to the single instance of the class.
macro singleton_class
  CLASSNAME = {{@type.stringify}}
  @@instance : {{@type}}?

  def self.instance
    inst = @@instance
    if inst
      return inst
    else
      raise "#{CLASSNAME} not instantiated!"
    end
  end

  def self.instantiated?
    !@@instance.nil?
  end

  def self.deinstantiate!
    @@instance = nil
  end
end

# Use this macro at the beginning of the `initialize` method.  It checks
# that the single instance of this class has not been created already.
macro singleton_pre_init
    raise self.class.name + " : only one instance can be created" if @@instance
end

# Use this macro at the end of the `initialize` method.  It creates
# the single instance of this class.
macro singleton_post_init
    @@instance = self
end

# Use this macro to define a class method that invokes the corresponding instance method.
macro singleton_method(name, *args)
  def {{ parse_type("CLASSNAME").resolve.id }}.{{name}}(*args)
    self.instance.{{name}}(*args)
  end
end
