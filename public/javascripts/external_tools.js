$(document).ready(function() {
  var $dialog = $("#external_tools_dialog");
  $(".add_tool_link").click(function(event) {
    event.preventDefault();
    var formData = {
      domain: "",
      url: "",
      description: "",
      name: "",
      privacy: "anonymous",
      consumer_key: "",
      shared_secret: ""
    }
    $dialog.dialog('close').dialog({
      autoOpen: false,
      title: "Edit External Tool",
      width: 600,
      height: 400
    }).dialog('open');
    $dialog.find(".shared_secret_note").hide();
    $dialog.find("form")
      .attr('method', 'POST')
      .attr('action', $dialog.find(".external_tools_url").attr('href'));
    $dialog.fillFormData(formData, {object_name: 'external_tool'});
    $("#external_tool_match_by").val('domain').change();
  });
  $dialog.find("form").formSubmit({
    beforeSubmit: function(data) {
      $(this).find("button").attr('disabled', true).filter('.save_button').text("Saving Tool Settings...");
    },
    success: function(tool) {
      $(this).find("button").attr('disabled', false).filter('.save_button').text("Save Tool Settings");
      $dialog.dialog('close');
      var $tool = $("#external_tool_" + tool.id);
      if($tool.length == 0) {
        $tool = $("#external_tool_blank").clone(true).removeAttr('id');
        $("#external_tools").append($tool);
      }
      $tool.fillTemplateData({
        data: tool,
        dataValues: ['id', 'workflow_state'],
        hrefValues: ['id'],
        id: 'external_tool_' + tool.id
      });
      $tool.find(".tool_url").showIf(tool.url).end()
        .find(".tool_domain").showIf(tool.domain);
      $tool.show();
    },
    error: function(data) {
      $(this).find("button").attr('disabled', false).filter('.save_button').text("Save Tool Settings Failed");
    }
  });
  $dialog.find(".cancel_button").click(function() {
    $dialog.dialog('close');
  });
  $("#external_tools").delegate('.edit_tool_link', 'click', function(event) {
    event.preventDefault();
    var $tool = $(this).parents(".external_tool");
    var data = $tool.getTemplateData({textValues: ['name', 'description', 'domain', 'url', 'consumer_key'], dataValues: ['id', 'workflow_state']});
    
    data.privacy_level = data.workflow_state;
    $("#external_tool_match_by").val(data.url ? 'url' : 'domain').change();
    $dialog.find(".shared_secret_note").show();
    $dialog.find("form")
      .attr('method', 'PUT')
      .attr('action', $tool.find(".update_tool_url").attr('rel'));
    $dialog.fillFormData(data, {object_name: 'external_tool'});
    $dialog.dialog('close').dialog({
      autoOpen: false,
      title: "Edit External Tool",
      width: 600,
      height: 400
    }).dialog('open');
  }).delegate('.delete_tool_link', 'click', function(event) {
    event.preventDefault();
    var $tool = $(this).parents(".external_tool");
    var url = $tool.find(".update_tool_url").attr('rel');
    $tool.confirmDelete({
      url: url,
      message: "Are you sure you want to remove this tool?  Any courses using this tool will no longer work.",
      success: function() {
        $(this).slideUp(function() {
          $(this).remove();
        });
      }
    });
  });
  $("#external_tool_match_by").change(function() {
    if($(this).val() == 'url') {
      $(this).parents("form").find(".tool_domain").hide().find(":text").val("").end().end()
        .find(".tool_url").show();
    } else {
      $(this).parents("form").find(".tool_url").hide().find(":text").val("").end().end()
        .find(".tool_domain").show();
    }
  });
});