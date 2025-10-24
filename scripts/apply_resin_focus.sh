#!/usr/bin/env bash
set -euo pipefail

repo_path="${1:-.}"

if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: $repo_path is not a Git repository." >&2
    exit 1
fi

required_files=(
    "src/libslic3r/Preset.cpp"
    "src/libslic3r/Preset.hpp"
    "src/libslic3r/PresetBundle.cpp"
    "src/libslic3r/PresetBundle.hpp"
    "src/libslic3r/PrintConfig.cpp"
    "src/slic3r/GUI/ConfigWizard.cpp"
    "src/slic3r/GUI/GLCanvas3D.cpp"
    "src/slic3r/GUI/GUI_App.cpp"
    "src/slic3r/GUI/MainFrame.cpp"
    "src/slic3r/GUI/Plater.cpp"
    "src/slic3r/GUI/Tab.hpp"
    "src/slic3r/Utils/PrintHost.cpp"
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$repo_path/$file" ]]; then
        echo "Error: Required file $file was not found in $repo_path." >&2
        exit 1
    fi
done

patch_file="$(mktemp)"
trap 'rm -f "$patch_file"' EXIT

cat <<'PATCH' > "$patch_file"
diff --git a/src/libslic3r/Preset.cpp b/src/libslic3r/Preset.cpp
index 0998ece..ec52323 100644
--- a/src/libslic3r/Preset.cpp
+++ b/src/libslic3r/Preset.cpp
@@ -183,12 +183,12 @@ VendorProfile VendorProfile::from_ini(const ptree &tree, const boost::filesystem
             model.id = section.first.substr(printer_model_key.size());
             model.name = section.second.get<std::string>("name", model.id);
 
-            const char *technology_fallback = boost::algorithm::starts_with(model.id, "SL") ? "SLA" : "FFF";
+            const char *technology_fallback = "SLA";
 
             auto technology_field = section.second.get<std::string>("technology", technology_fallback);
             if (! ConfigOptionEnum<PrinterTechnology>::from_string(technology_field, model.technology)) {
                 BOOST_LOG_TRIVIAL(error) << boost::format("Vendor bundle: `%1%`: Invalid printer technology field: `%2%`") % id % technology_field;
-                model.technology = ptFFF;
+                model.technology = ptSLA;
             }
 
             model.family = section.second.get<std::string>("family", std::string());
@@ -1692,8 +1692,8 @@ std::string PresetCollection::path_from_name(const std::string &new_name) const
 
 const Preset& PrinterPresetCollection::default_preset_for(const DynamicPrintConfig &config) const
 {
-    const ConfigOptionEnumGeneric *opt_printer_technology = config.opt<ConfigOptionEnumGeneric>("printer_technology");
-    return this->default_preset((opt_printer_technology == nullptr || opt_printer_technology->value == ptFFF) ? 0 : 1);
+    (void)config;
+    return this->default_preset();
 }
 
 const Preset* PrinterPresetCollection::find_system_preset_by_model_and_variant(const std::string &model_id, const std::string& variant) const
diff --git a/src/libslic3r/Preset.hpp b/src/libslic3r/Preset.hpp
index c2f3c35..18497f6 100644
--- a/src/libslic3r/Preset.hpp
+++ b/src/libslic3r/Preset.hpp
@@ -203,13 +203,13 @@ public:
     }
     const std::string&  compatible_printers_condition() const { return const_cast<Preset*>(this)->compatible_printers_condition(); }
 
-    // Return a printer technology, return ptFFF if the printer technology is not set.
+    // Return a printer technology, return ptSLA if the printer technology is not set.
     static PrinterTechnology printer_technology(const DynamicPrintConfig &cfg) {
         auto *opt = cfg.option<ConfigOptionEnum<PrinterTechnology>>("printer_technology");
-        // The following assert may trigger when importing some legacy profile, 
+        // The following assert may trigger when importing some legacy profile,
         // but it is safer to keep it here to capture the cases where the "printer_technology" key is queried, where it should not.
 //        assert(opt != nullptr);
-        return (opt == nullptr) ? ptFFF : opt->value;
+        return (opt == nullptr) ? ptSLA : opt->value;
     }
     PrinterTechnology   printer_technology() const { return Preset::printer_technology(this->config); }
     // This call returns a reference, it may add a new entry into the DynamicPrintConfig.
@@ -705,12 +705,12 @@ public:
     bool                delete_preset(const std::string& preset_name);
     void                reset_presets();
 
-    // Return a printer technology, return ptFFF if the printer technology is not set.
+    // Return a printer technology, return ptSLA if the printer technology is not set.
     static PrinterTechnology printer_technology(const DynamicPrintConfig& cfg) {
         auto* opt = cfg.option<ConfigOptionEnum<PrinterTechnology>>("printer_technology");
         // The following assert may trigger when importing some legacy profile, 
         // but it is safer to keep it here to capture the cases where the "printer_technology" key is queried, where it should not.
-        return (opt == nullptr) ? ptFFF : opt->value;
+        return (opt == nullptr) ? ptSLA : opt->value;
     }
     PrinterTechnology   printer_technology() const { return printer_technology(this->config); }
 
diff --git a/src/libslic3r/PresetBundle.cpp b/src/libslic3r/PresetBundle.cpp
index 04b8845..2ac8aa4 100644
--- a/src/libslic3r/PresetBundle.cpp
+++ b/src/libslic3r/PresetBundle.cpp
@@ -49,7 +49,7 @@ PresetBundle::PresetBundle() :
     filaments(Preset::TYPE_FILAMENT, Preset::filament_options(), static_cast<const PrintRegionConfig&>(FullPrintConfig::defaults())),
     sla_materials(Preset::TYPE_SLA_MATERIAL, Preset::sla_material_options(), static_cast<const SLAMaterialConfig&>(SLAFullPrintConfig::defaults())), 
     sla_prints(Preset::TYPE_SLA_PRINT, Preset::sla_print_options(), static_cast<const SLAPrintObjectConfig&>(SLAFullPrintConfig::defaults())),
-    printers(Preset::TYPE_PRINTER, Preset::printer_options(), static_cast<const PrintRegionConfig&>(FullPrintConfig::defaults()), "- default FFF -"),
+    printers(Preset::TYPE_PRINTER, Preset::printer_options(), static_cast<const PrintRegionConfig&>(FullPrintConfig::defaults()), "- default SLA -"),
     physical_printers(PhysicalPrinter::printer_options(), this)
 {
     // The following keys are handled by the UI, they do not have a counterpart in any StaticPrintConfig derived classes,
@@ -82,27 +82,19 @@ PresetBundle::PresetBundle() :
     this->sla_prints.default_preset().compatible_printers_condition();
     this->sla_prints.default_preset().inherits();
 
-    this->printers.add_default_preset(Preset::sla_printer_options(), static_cast<const SLAMaterialConfig&>(SLAFullPrintConfig::defaults()), "- default SLA -");
-    this->printers.preset(1).printer_technology_ref() = ptSLA;
-    for (size_t i = 0; i < 2; ++ i) {
-		// The following ugly switch is to avoid printers.preset(0) to return the edited instance, as the 0th default is the current one.
-		Preset &preset = this->printers.default_preset(i);
-        for (const char *key : { 
-            "printer_settings_id", "printer_vendor", "printer_model", "printer_variant", "thumbnails",
-            //FIXME the following keys are only created here for compatibility to be able to parse legacy Printer profiles.
-            // These keys are converted to Physical Printer profile. After the conversion, they shall be removed.
-            "host_type", "print_host", "printhost_apikey", "printhost_cafile"})
-            preset.config.optptr(key, true);
-        if (i == 0) {
-            preset.config.optptr("default_print_profile", true);
-            preset.config.option<ConfigOptionStrings>("default_filament_profile", true);
-        } else {
-            preset.config.optptr("default_sla_print_profile", true);
-            preset.config.optptr("default_sla_material_profile", true);
-        }
-        // default_sla_material_profile
-        preset.inherits();
-    }
+    Preset &sla_default = this->printers.default_preset();
+    sla_default.printer_technology_ref() = ptSLA;
+    for (const char *key : {
+        "printer_settings_id", "printer_vendor", "printer_model", "printer_variant", "thumbnails",
+        //FIXME the following keys are only created here for compatibility to be able to parse legacy Printer profiles.
+        // These keys are converted to Physical Printer profile. After the conversion, they shall be removed.
+        "host_type", "print_host", "printhost_apikey", "printhost_cafile"})
+        sla_default.config.optptr(key, true);
+    sla_default.config.optptr("default_print_profile", true);
+    sla_default.config.option<ConfigOptionStrings>("default_filament_profile", true);
+    sla_default.config.optptr("default_sla_print_profile", true);
+    sla_default.config.optptr("default_sla_material_profile", true);
+    sla_default.inherits();
 
     // Re-activate the default presets, so their "edited" preset copies will be updated with the additional configuration values above.
     this->prints       .select_preset(0);
@@ -455,8 +447,13 @@ static inline std::string remove_ini_suffix(const std::string &name)
 void PresetBundle::load_installed_printers(const AppConfig &config)
 {
 	this->update_system_maps();
-    for (auto &preset : printers)
+    for (auto &preset : printers) {
+        if (preset.printer_technology() != ptSLA) {
+            preset.is_visible = false;
+            continue;
+        }
         preset.set_visible_from_appconfig(config);
+    }
 }
 
 void PresetBundle::cache_extruder_filaments_names()
@@ -672,6 +669,16 @@ void PresetBundle::load_selections(AppConfig &config, const PresetPreferences& p
     const Preset *preferred_printer = printers.find_system_preset_by_model_and_variant(preferred_selection.printer_model_id, preferred_selection.printer_variant);
     printers.select_preset_by_name(preferred_printer ? preferred_printer->name : initial_printer_profile_name, true);
 
+    if (printers.get_selected_preset().printer_technology() != ptSLA) {
+        for (size_t i = 0; i < printers.size(); ++i) {
+            const Preset &candidate = printers.preset(i, false);
+            if (candidate.printer_technology() == ptSLA && candidate.is_visible) {
+                printers.select_preset(i);
+                break;
+            }
+        }
+    }
+
     // Selects the profile, leaves it to -1 if the initial profile name is empty or if it was not found.
     prints.select_preset_by_name_strict(initial_print_profile_name);
     filaments.select_preset_by_name_strict(initial_filament_profile_name);
@@ -873,7 +880,7 @@ DynamicPrintConfig PresetBundle::full_fff_config() const
     add_if_some_non_empty(std::move(compatible_prints_condition),   "compatible_prints_condition_cummulative");
     add_if_some_non_empty(std::move(inherits),                      "inherits_cummulative");
 
-	out.option<ConfigOptionEnumGeneric>("printer_technology", true)->value = ptFFF;
+        out.option<ConfigOptionEnumGeneric>("printer_technology", true)->value = ptSLA;
     return out;
 }
 
diff --git a/src/libslic3r/PresetBundle.hpp b/src/libslic3r/PresetBundle.hpp
index 06374a1..4c5bc5a 100644
--- a/src/libslic3r/PresetBundle.hpp
+++ b/src/libslic3r/PresetBundle.hpp
@@ -52,8 +52,8 @@ public:
     PresetCollection            sla_prints;
     PresetCollection            filaments;
     PresetCollection            sla_materials;
-	PresetCollection& 			materials(PrinterTechnology pt)       { return pt == ptFFF ? this->filaments : this->sla_materials; }
-	const PresetCollection& 	materials(PrinterTechnology pt) const { return pt == ptFFF ? this->filaments : this->sla_materials; }
+	PresetCollection& 			materials(PrinterTechnology /*pt*/)       { return this->sla_materials; }
+	const PresetCollection& 	materials(PrinterTechnology /*pt*/) const { return this->sla_materials; }
     PrinterPresetCollection     printers;
     PhysicalPrinterCollection   physical_printers;
 
@@ -195,9 +195,7 @@ public:
 
     static const char *PRUSA_BUNDLE;
 
-    static std::array<Preset::Type, 3>  types_list(PrinterTechnology pt) {
-        if (pt == ptFFF)
-            return  { Preset::TYPE_PRINTER, Preset::TYPE_PRINT, Preset::TYPE_FILAMENT };
+    static std::array<Preset::Type, 3>  types_list(PrinterTechnology /*pt*/) {
         return      { Preset::TYPE_PRINTER, Preset::TYPE_SLA_PRINT, Preset::TYPE_SLA_MATERIAL };
     }
 
diff --git a/src/libslic3r/PrintConfig.cpp b/src/libslic3r/PrintConfig.cpp
index 865a8f4..bc31262 100644
--- a/src/libslic3r/PrintConfig.cpp
+++ b/src/libslic3r/PrintConfig.cpp
@@ -5507,7 +5507,7 @@ std::string DynamicPrintConfig::validate()
 {
     // Full print config is initialized from the defaults.
     const ConfigOption *opt = this->option("printer_technology", false);
-    auto printer_technology = (opt == nullptr) ? ptFFF : static_cast<PrinterTechnology>(dynamic_cast<const ConfigOptionEnumGeneric*>(opt)->value);
+    auto printer_technology = (opt == nullptr) ? ptSLA : static_cast<PrinterTechnology>(dynamic_cast<const ConfigOptionEnumGeneric*>(opt)->value);
     switch (printer_technology) {
     case ptFFF:
     {
diff --git a/src/slic3r/GUI/ConfigWizard.cpp b/src/slic3r/GUI/ConfigWizard.cpp
index 97fb0ec..6eddbc4 100644
--- a/src/slic3r/GUI/ConfigWizard.cpp
+++ b/src/slic3r/GUI/ConfigWizard.cpp
@@ -2820,18 +2820,12 @@ ConfigWizard::priv::Repository* ConfigWizard::priv::get_repo(const std::string&
 
 void ConfigWizard::priv::create_vendor_printers_page(const std::string& repo_id, const VendorProfile* vendor, bool install/* = false*/, bool from_single_vendor_repo /*= false*/)
 {
-    bool is_fff_technology = false;
     bool is_sla_technology = false;
 
     for (auto& model: vendor->models)
     {
-        if (!is_fff_technology && model.technology == ptFFF)
-            is_fff_technology = true;
         if (!is_sla_technology && model.technology == ptSLA)
             is_sla_technology = true;
-
-        if (is_fff_technology && is_sla_technology)
-            break;
     }
 
     PagePrinters* pageFFF = nullptr;
@@ -2840,16 +2834,7 @@ void ConfigWizard::priv::create_vendor_printers_page(const std::string& repo_id,
     const bool is_prusa_vendor = vendor->name.find("Prusa") != std::string::npos;
     const unsigned indent = from_single_vendor_repo ? 0 : 1;
 
-    if (is_fff_technology) 
-    {
-        pageFFF = new PagePrinters(q, vendor->name + " " +_L("FFF Technology Printers"), vendor->name + (is_prusa_vendor ? "" : " FFF"), *vendor, indent, T_FFF);
-        pageFFF->install = install;
-        if (only_sla_mode)
-            only_sla_mode = false;
-        add_page(pageFFF);
-    }
-
-    if (is_sla_technology) 
+    if (is_sla_technology)
     {
         pageSLA = new PagePrinters(q, vendor->name + " " + _L("SLA Technology Printers"), vendor->name + (is_prusa_vendor ? "" : " MLSA"), *vendor, indent, T_SLA);
         pageSLA->install = install;
diff --git a/src/slic3r/GUI/GLCanvas3D.cpp b/src/slic3r/GUI/GLCanvas3D.cpp
index 3776e41..c8ac127 100644
--- a/src/slic3r/GUI/GLCanvas3D.cpp
+++ b/src/slic3r/GUI/GLCanvas3D.cpp
@@ -1281,8 +1281,8 @@ void GLCanvas3D::SLAView::select_full_instance(const GLVolume::CompositeID& id)
 
 PrinterTechnology GLCanvas3D::current_printer_technology() const
 {
-    return m_process ? m_process->current_printer_technology() : ptFFF;
-}
+    return m_process ? m_process->current_printer_technology() : ptSLA;
+}
 
 bool GLCanvas3D::is_arrange_alignment_enabled() const
 {
diff --git a/src/slic3r/GUI/GUI_App.cpp b/src/slic3r/GUI/GUI_App.cpp
index 38c6a8b..c8f1c15 100644
--- a/src/slic3r/GUI/GUI_App.cpp
+++ b/src/slic3r/GUI/GUI_App.cpp
@@ -1616,8 +1616,8 @@ bool GUI_App::on_init_inner()
     if (is_gcode_viewer()) {
         mainframe->update_layout();
         if (plater_ != nullptr)
-            // ensure the selected technology is ptFFF
-            plater_->set_printer_technology(ptFFF);
+            // ensure the selected technology is ptSLA
+            plater_->set_printer_technology(ptSLA);
     }
     else
         load_current_presets();
diff --git a/src/slic3r/GUI/MainFrame.cpp b/src/slic3r/GUI/MainFrame.cpp
index aa19984..d009f15 100644
--- a/src/slic3r/GUI/MainFrame.cpp
+++ b/src/slic3r/GUI/MainFrame.cpp
@@ -799,11 +799,9 @@ void MainFrame::register_win32_callbacks()
 
 void MainFrame::create_preset_tabs()
 {
-    add_created_tab(new TabPrint(m_tabpanel), "cog");
-    add_created_tab(new TabFilament(m_tabpanel), "spool");
     add_created_tab(new TabSLAPrint(m_tabpanel), "cog");
     add_created_tab(new TabSLAMaterial(m_tabpanel), "resin");
-    add_created_tab(new TabPrinter(m_tabpanel), wxGetApp().preset_bundle->printers.get_edited_preset().printer_technology() == ptFFF ? "printer" : "sla_printer");
+    add_created_tab(new TabPrinter(m_tabpanel), "sla_printer");
     
     m_printables_webview = new PrintablesWebViewPanel(m_tabpanel);
     add_printables_webview_tab();
diff --git a/src/slic3r/GUI/Plater.cpp b/src/slic3r/GUI/Plater.cpp
index 9c6b45e..c0821e4 100644
--- a/src/slic3r/GUI/Plater.cpp
+++ b/src/slic3r/GUI/Plater.cpp
@@ -271,7 +271,7 @@ struct Plater::priv
     std::vector<std::unique_ptr<Slic3r::Print>>     fff_prints;
     std::vector<std::unique_ptr<Slic3r::SLAPrint>> sla_prints;
     Slic3r::Model               model;
-    PrinterTechnology           printer_technology = ptFFF;
+    PrinterTechnology           printer_technology = ptSLA;
     std::vector<Slic3r::GCodeProcessorResult> gcode_results;
 
     // GUI elements
diff --git a/src/slic3r/GUI/Tab.hpp b/src/slic3r/GUI/Tab.hpp
index 1d0dd6b..908b514 100644
--- a/src/slic3r/GUI/Tab.hpp
+++ b/src/slic3r/GUI/Tab.hpp
@@ -532,7 +532,7 @@ public:
 	size_t		m_sys_extruders_count;
 	size_t		m_cache_extruder_count = 0;
 
-    PrinterTechnology               m_printer_technology = ptFFF;
+    PrinterTechnology               m_printer_technology = ptSLA;
 
     TabPrinter(wxBookCtrlBase* parent) :
         Tab(parent, _L("Printers"), Slic3r::Preset::TYPE_PRINTER) {}
diff --git a/src/slic3r/Utils/PrintHost.cpp b/src/slic3r/Utils/PrintHost.cpp
index 03a72e7..b84d5f6 100644
--- a/src/slic3r/Utils/PrintHost.cpp
+++ b/src/slic3r/Utils/PrintHost.cpp
@@ -43,7 +43,7 @@ PrintHost::~PrintHost() {}
 
 PrintHost* PrintHost::get_print_host(DynamicPrintConfig *config)
 {
-    PrinterTechnology tech = ptFFF;
+    PrinterTechnology tech = ptSLA;
 
     {
         const auto opt = config->option<ConfigOptionEnum<PrinterTechnology>>("printer_technology");
PATCH

if git -C "$repo_path" apply --check "$patch_file"; then
    git -C "$repo_path" apply "$patch_file"
    echo "Applied resin-focused patch to $repo_path."
elif git -C "$repo_path" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Patch already applied in $repo_path."
else
    echo "Error: Patch did not apply cleanly to $repo_path." >&2
    exit 1
fi
