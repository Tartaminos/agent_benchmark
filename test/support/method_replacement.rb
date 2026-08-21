module MethodReplacement
  def with_replaced_singleton_method(object, method_name, replacement)
    singleton_class = object.singleton_class
    original_method = object.method(method_name)
    singleton_class.define_method(method_name, &replacement)
    yield
  ensure
    singleton_class.define_method(method_name, original_method)
  end
end
