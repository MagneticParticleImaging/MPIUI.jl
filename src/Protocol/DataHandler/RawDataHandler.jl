include("StorageParameter.jl")

mutable struct RawDataHandler <: AbstractDataHandler
  dataWidget::RawDataWidget
  params::StorageParameter
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol 
end

function RawDataHandler(scanner=nothing)
  data = RawDataWidget()
  # Init Display Widget
  updateData(data, ones(Float32,10,1,1,1), 1.0)
  return RawDataHandler(data, StorageParameter(scanner), true, true)
end

function isready(widget::RawDataHandler)
  ready = @atomic widget.ready
  enabled = @atomic widget.enabled
  return ready && enabled
end
enable!(widget::RawDataHandler, val::Bool) = @atomic widget.enabled = val
getParameterTitle(widget::RawDataHandler) = "Raw Data"
getParameterWidget(widget::RawDataHandler) = widget.params
getDisplayTitle(widget::RawDataHandler) = "Raw Data"
getDisplayWidget(widget::RawDataHandler) = widget.dataWidget

function updateData(widget::RawDataHandler, data)
  @atomic widget.ready = false
  @idle_add_guarded begin

    @atomic widget.ready = true
  end
end