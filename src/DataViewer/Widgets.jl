
struct DVWidgets
  gridDataViewer2D::Grid
  gridDataViewer3D::Grid
  cbCMaps::ComboBoxTextLeaf
  cbCMapsBG::ComboBoxTextLeaf
  cbPermutes::ComboBoxTextLeaf
  cbFlips::ComboBoxTextLeaf
  cbFrameProj::ComboBoxTextLeaf
  cbChannel::ComboBoxTextLeaf
  cbProfile::ComboBoxTextLeaf
  mbFusion::ToggleButtonLeaf
  lbFusion::LabelLeaf
  lbChannel::LabelLeaf
  sepFusion::Gtk.GtkWidgetLeaf
  labelFrames::LabelLeaf
  spinFrames::SpinButtonLeaf
  btnPlayMovie::ToggleButtonLeaf
  adjFrames::AdjustmentLeaf
  adjSliceX::AdjustmentLeaf
  adjSliceY::AdjustmentLeaf
  adjSliceZ::AdjustmentLeaf
  adjCMin::AdjustmentLeaf
  adjCMax::AdjustmentLeaf
  adjCMinBG::AdjustmentLeaf
  adjCMaxBG::AdjustmentLeaf
  adjTransX::AdjustmentLeaf
  adjTransY::AdjustmentLeaf
  adjTransZ::AdjustmentLeaf
  adjRotX::AdjustmentLeaf
  adjRotY::AdjustmentLeaf
  adjRotZ::AdjustmentLeaf
  adjTransBGX::AdjustmentLeaf
  adjTransBGY::AdjustmentLeaf
  adjTransBGZ::AdjustmentLeaf
  adjRotBGX::AdjustmentLeaf
  adjRotBGY::AdjustmentLeaf
  adjRotBGZ::AdjustmentLeaf
  adjTTPThresh::AdjustmentLeaf
  adjPixelResizeFactor::AdjustmentLeaf
  cbSpatialMIP::CheckButtonLeaf
  cbShowSlices::CheckButtonLeaf
  cbHideFG::CheckButtonLeaf
  cbHideBG::CheckButtonLeaf
  cbBlendChannels::CheckButtonLeaf
  cbShowSFFOV::CheckButtonLeaf
  cbTranslucentBlending::CheckButtonLeaf
  cbSpatialBGMIP::CheckButtonLeaf
  cbShowDFFOV::CheckButtonLeaf
  btnSaveVisu::ButtonLeaf
  btnExportImages::ButtonLeaf
  btnExportTikz::ButtonLeaf
  btnExportMovi::ButtonLeaf
  btnExportAllData::ButtonLeaf
  btnExportRealDataAllFr::ButtonLeaf
  btnExportData::ButtonLeaf
  btnExportProfile::ButtonLeaf
  entVisuName::EntryLeaf
  nb2D3D::NotebookLeaf
end

function DVWidgets(b::Builder)
  return DVWidgets(
    obj(b,"gridDataViewer2D", Grid),
    obj(b,"gridDataViewer3D", Grid),
    obj(b,"cbCMaps", ComboBoxTextLeaf),
    obj(b,"cbCMapsBG", ComboBoxTextLeaf),
    obj(b,"cbPermutes", ComboBoxTextLeaf),
    obj(b,"cbFlips", ComboBoxTextLeaf),
    obj(b,"cbFrameProj", ComboBoxTextLeaf),
    obj(b,"cbChannel", ComboBoxTextLeaf),
    obj(b,"cbProfile", ComboBoxTextLeaf),
    obj(b,"mbFusion", ToggleButtonLeaf),
    obj(b,"lbFusion", LabelLeaf),
    obj(b,"lbChannel", LabelLeaf),
    obj(b,"sepFusion", Gtk.GtkWidgetLeaf),
    obj(b,"labelFrames", LabelLeaf),
    obj(b,"spinFrames", SpinButtonLeaf),
    obj(b,"btnPlayMovie", ToggleButtonLeaf),
    obj(b,"adjFrames", AdjustmentLeaf),
    obj(b,"adjSliceX", AdjustmentLeaf),
    obj(b,"adjSliceY", AdjustmentLeaf),
    obj(b,"adjSliceZ", AdjustmentLeaf),
    obj(b,"adjCMin", AdjustmentLeaf),
    obj(b,"adjCMax", AdjustmentLeaf),
    obj(b,"adjCMinBG", AdjustmentLeaf),
    obj(b,"adjCMaxBG", AdjustmentLeaf),
    obj(b,"adjTransX", AdjustmentLeaf),
    obj(b,"adjTransY", AdjustmentLeaf),
    obj(b,"adjTransZ", AdjustmentLeaf),
    obj(b,"adjRotX", AdjustmentLeaf),
    obj(b,"adjRotY", AdjustmentLeaf),
    obj(b,"adjRotZ", AdjustmentLeaf),
    obj(b,"adjTransBGX", AdjustmentLeaf),
    obj(b,"adjTransBGY", AdjustmentLeaf),
    obj(b,"adjTransBGZ", AdjustmentLeaf),
    obj(b,"adjRotBGX", AdjustmentLeaf),
    obj(b,"adjRotBGY", AdjustmentLeaf),
    obj(b,"adjRotBGZ", AdjustmentLeaf),
    obj(b,"adjTTPThresh", AdjustmentLeaf),
    obj(b,"adjPixelResizeFactor", AdjustmentLeaf),
    obj(b,"cbSpatialMIP", CheckButtonLeaf),
    obj(b,"cbShowSlices", CheckButtonLeaf),
    obj(b,"cbHideFG", CheckButtonLeaf),
    obj(b,"cbHideBG", CheckButtonLeaf),
    obj(b,"cbBlendChannels", CheckButtonLeaf),
    obj(b,"cbShowSFFOV", CheckButtonLeaf),
    obj(b,"cbTranslucentBlending", CheckButtonLeaf),
    obj(b,"cbSpatialBGMIP", CheckButtonLeaf),
    obj(b,"cbShowDFFOV", CheckButtonLeaf),
    obj(b,"btnSaveVisu", ButtonLeaf),
    obj(b,"btnExportImages", ButtonLeaf),
    obj(b,"btnExportTikz", ButtonLeaf),
    obj(b,"btnExportMovi", ButtonLeaf),
    obj(b,"btnExportAllData", ButtonLeaf),
    obj(b,"btnExportRealDataAllFr", ButtonLeaf),
    obj(b,"btnExportData", ButtonLeaf),
    obj(b,"btnExportProfile", ButtonLeaf),
    obj(b,"entVisuName", EntryLeaf),
    obj(b,"nb2D3D", NotebookLeaf)
  )
end
