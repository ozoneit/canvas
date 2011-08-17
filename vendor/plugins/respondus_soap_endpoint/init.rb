Rails.configuration.to_prepare do
  require_dependency 'respondus_soap_endpoint_plugin_validator'
  plugin = Canvas::Plugin.register :respondus_soap_endpoint, nil, {
          :name =>'Respondus SOAP Endpoint',
          :author => 'instructure',
          :author_website => 'http://www.instructure.com',
          :description => 'SOAP Endpoint for Respondus QTI uploads',
          :version => '1.0.0',
          :settings_partial => 'plugins/respondus_soap_endpoint_settings',
          :settings => {
            :enabled => false,
            :worker => 'QtiWorker'
          },
          :validator => 'RespondusSoapEndpointPluginValidator'
  }

  # ActionController::ParamsParser sees that the request body is XML, reads
  # the entire thing, and parses into an ActionPack params structure. This is
  # so not what we want, so we make sure this middleware comes first.
  # I guess we just gotta hope that no middlewares after that one have any
  # useful-to-this-plugin functionality. At least we still get the AR query
  # cache.
  Rails.configuration.middleware.insert_before 'ActionController::ParamsParser', 'RespondusAPIMiddleware'
end
