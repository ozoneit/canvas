/**
 * Copyright (C) 2011 Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

$(function(){
  var $config_options = $("#config_options"),
      $export_file_enabled = $("#export_file_enabled"),
      $migration_form = $('#migration_form'),
      $submit_button = $migration_form.find(".submit_button"),
      $file_upload = $migration_form.find("#file_upload"),
      $export_file_input = $migration_form.find("#export_file_input"),
      $migration_config = $migration_form.find("#migration_config"),
      $migration_configs = $("#migration_configs"),
      $migration_alt_div = $("#migration_alt_div");

  function enableFileUpload(){
    $export_file_enabled.val("1");
    $file_upload.show();
  }

  function resetMigrationForm(){
    $config_options.find("#migration_config > div").hide();
    $export_file_enabled.val("0");
    $file_upload.hide();
    $export_file_input.val("");
    $submit_button.attr('disabled', true);

    $migration_config.find(".migration_config").ifExists(function(){
      $plugin_mother = $migration_configs.find($(this).data("mother_id"));
      $plugin_mother.append($(this));
      $plugin_mother.triggerHandler("pluginHidden", [$migration_form, $migration_alt_div]);

      $alt_config = $migration_alt_div.find(".migration_alt_config");
      if($alt_config){
        $plugin_mother.append($alt_config);
      }          
    });
  }

  $("#choose_migration_system").change(function() {
    resetMigrationForm();
    
    if($(this).val() == "none") {
      $config_options.hide();
    } else {
      plugin_config_id = "#plugin_" + $(this).val();
      $plugin_mother_div = $migration_configs.find(plugin_config_id);
      $plugin_config = $plugin_mother_div.find(".migration_config");
      $plugin_config.data("mother_id", plugin_config_id);
      $migration_config.append($plugin_config);
      $plugin_alt_config = $plugin_mother_div.find(".migration_alt_config");
      if($plugin_alt_config){
        $plugin_alt_config.data("mother_id", plugin_config_id);
        $migration_alt_div.append($plugin_alt_config);
      }

      $config_options.show();
      $plugin_mother_div.triggerHandler("pluginShown", [enableFileUpload, $migration_form, $migration_alt_div]);
    }
  }).change();

  $("#import_subset").change(function() {
    $("#import_subset_options").showIf($(this).attr('checked'));
  }).change();

  $("#export_file_input").change(function() {
    if($(this).val().match(/\.zip$/i)) {
      $submit_button.attr('disabled', false);
      $('.zip_error').hide();
    } else {
      $submit_button.attr('disabled', true);
      $('.zip_error').show();
    }
  });

  $("#migration_form").formSubmit({
    fileUpload: function() {
      return $migration_form.hasClass('file_upload');
    },
    processData: function(data) {
      if(!$(this).hasClass('file_upload')){
        data['export_file'] = null;
      }
      return data;
    },
    beforeSubmit: function(data) {
      $(this).find(".submit_button").attr('disabled', true).text("Uploading Course Export...");
    },
    success: function(data) {
      $(this).slideUp();
      $("#file_uploaded").slideDown();
    },
    error: function(data) {
      $(this).formErrors(data);
    }
  });

});