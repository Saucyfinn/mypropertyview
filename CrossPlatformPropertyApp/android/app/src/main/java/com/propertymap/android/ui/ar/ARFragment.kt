package com.propertymap.android.ui.ar

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.propertymap.android.MainActivity
import com.propertymap.android.databinding.FragmentArBinding
import com.propertymap.android.data.PropertyBoundaryData
import com.propertymap.android.ar.ARCoreManager

/**
 * AR fragment that displays property boundaries in augmented reality
 * Uses ARCore for positioning and rendering
 */
class ARFragment : Fragment() {

    private var _binding: FragmentArBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var arViewModel: ARViewModel
    private var arCoreManager: ARCoreManager? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        arViewModel = ViewModelProvider(this)[ARViewModel::class.java]
        _binding = FragmentArBinding.inflate(inflater, container, false)
        val root: View = binding.root

        setupArView()
        observeViewModel()
        setupPropertyBridge()

        return root
    }
    
    private fun setupArView() {
        // Initialize ARCore manager
        arCoreManager = ARCoreManager(requireContext(), binding.arSceneView)
        
        // Set up AR scene
        arCoreManager?.initialize { success ->
            if (success) {
                binding.statusText.text = "AR initialized - Point camera to see property boundaries"
            } else {
                binding.statusText.text = "AR not available on this device"
                Toast.makeText(context, "ARCore not supported", Toast.LENGTH_LONG).show()
            }
        }
    }
    
    private fun observeViewModel() {
        arViewModel.statusText.observe(viewLifecycleOwner) { status ->
            binding.statusText.text = status
        }
        
        arViewModel.propertyData.observe(viewLifecycleOwner) { propertyData ->
            propertyData?.let {
                displayPropertyBoundaries(it)
            }
        }
    }
    
    private fun setupPropertyBridge() {
        // Register for property data from web interface
        (activity as? MainActivity)?.getPropertyBridge()?.setArCallback { propertyData ->
            requireActivity().runOnUiThread {
                arViewModel.setPropertyData(propertyData)
            }
        }
    }
    
    private fun displayPropertyBoundaries(propertyData: PropertyBoundaryData) {
        arCoreManager?.displayBoundaries(
            coordinates = propertyData.coordinates.map { 
                Pair(it.latitude, it.longitude) 
            },
            propertyInfo = propertyData.property
        )
        
        binding.statusText.text = "Displaying ${propertyData.property.appellation}"
    }
    
    override fun onResume() {
        super.onResume()
        arCoreManager?.onResume()
    }
    
    override fun onPause() {
        super.onPause()
        arCoreManager?.onPause()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        arCoreManager?.cleanup()
        _binding = null
    }
}