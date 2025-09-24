package com.propertymap.android.ui.ar

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.propertymap.android.data.PropertyBoundaryData

/**
 * ViewModel for AR fragment to manage property data and status
 */
class ARViewModel : ViewModel() {

    private val _statusText = MutableLiveData<String>().apply {
        value = "Initializing AR..."
    }
    val statusText: LiveData<String> = _statusText

    private val _propertyData = MutableLiveData<PropertyBoundaryData?>()
    val propertyData: LiveData<PropertyBoundaryData?> = _propertyData
    
    fun setStatusText(status: String) {
        _statusText.value = status
    }
    
    fun setPropertyData(data: PropertyBoundaryData) {
        _propertyData.value = data
    }
    
    fun clearPropertyData() {
        _propertyData.value = null
    }
}