using NativeEngine;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Sandbox.Rendering;

/// <summary>
/// A hardware ray tracing accelerator that communicates directly with the Vulkan API.
/// This bypasses any existing engine ray tracing code to provide a clean, high-performance implementation.
/// </summary>
public class VulkanRayTracingAccelerator : RenderExtension
{
	#region Vulkan Interop
	private const string VULKAN_LIB = "vulkan-1.dll";

	[DllImport( VULKAN_LIB, CallingConvention = CallingConvention.StdCall )]
	private static extern IntPtr vkGetDeviceProcAddr( IntPtr device, [MarshalAs(UnmanagedType.LPStr)] string pName );

	private delegate int vkCreateAccelerationStructureKHRDelegate( IntPtr device, ref VkAccelerationStructureCreateInfoKHR pCreateInfo, IntPtr pAllocator, out ulong pAccelerationStructure );
	private delegate void vkDestroyAccelerationStructureKHRDelegate( IntPtr device, ulong accelerationStructure, IntPtr pAllocator );
	private delegate void vkCmdBuildAccelerationStructuresKHRDelegate( IntPtr commandBuffer, uint infoCount, ref VkAccelerationStructureBuildGeometryInfoKHR pInfos, IntPtr ppBuildRangeInfos );
	private delegate void vkGetAccelerationStructureBuildSizesKHRDelegate( IntPtr device, VkAccelerationStructureBuildTypeKHR buildType, ref VkAccelerationStructureBuildGeometryInfoKHR pBuildInfo, uint[] pMaxPrimitiveCounts, out VkAccelerationStructureBuildSizesInfoKHR pSizeInfo );
	private delegate ulong vkGetAccelerationStructureDeviceAddressKHRDelegate( IntPtr device, ref VkAccelerationStructureDeviceAddressInfoKHR pInfo );

	private vkCreateAccelerationStructureKHRDelegate vkCreateAccelerationStructureKHR;
	private vkDestroyAccelerationStructureKHRDelegate vkDestroyAccelerationStructureKHR;
	private vkCmdBuildAccelerationStructuresKHRDelegate vkCmdBuildAccelerationStructuresKHR;
	private vkGetAccelerationStructureBuildSizesKHRDelegate vkGetAccelerationStructureBuildSizesKHR;
	private vkGetAccelerationStructureDeviceAddressKHRDelegate vkGetAccelerationStructureDeviceAddressKHR;

	[StructLayout( LayoutKind.Sequential )]
	private struct VkAccelerationStructureCreateInfoKHR
	{
		public int sType;
		public IntPtr pNext;
		public int createFlags;
		public ulong buffer;
		public ulong offset;
		public ulong size;
		public int type;
		public ulong deviceAddress;
	}

	[StructLayout( LayoutKind.Sequential )]
	private struct VkAccelerationStructureBuildGeometryInfoKHR
	{
		public int sType;
		public IntPtr pNext;
		public int type;
		public int flags;
		public int mode;
		public ulong srcAccelerationStructure;
		public ulong dstAccelerationStructure;
		public uint geometryCount;
		public IntPtr pGeometries;
		public IntPtr ppGeometries;
		public ulong scratchData;
	}

	[StructLayout( LayoutKind.Sequential )]
	private struct VkAccelerationStructureBuildSizesInfoKHR
	{
		public int sType;
		public IntPtr pNext;
		public ulong accelerationStructureSize;
		public ulong updateScratchSize;
		public ulong buildScratchSize;
	}

	[StructLayout( LayoutKind.Sequential )]
	private struct VkAccelerationStructureDeviceAddressInfoKHR
	{
		public int sType;
		public IntPtr pNext;
		public ulong accelerationStructure;
	}

	private enum VkAccelerationStructureBuildTypeKHR
	{
		Host = 0,
		Device = 1
	}
	#endregion

	private bool _initialized;
	private List<ulong> _bottomLevelAS = new();
	private ulong _topLevelAS;

	/// <summary>
	/// Returns the Top-Level Acceleration Structure handle.
	/// </summary>
	public ulong TopLevelAS => _topLevelAS;

	/// <summary>
	/// Returns the list of Bottom-Level Acceleration Structure handles.
	/// </summary>
	public IReadOnlyList<ulong> BottomLevelAS => _bottomLevelAS;

	public VulkanRayTracingAccelerator()
	{
		InitializeVulkanFunctions();
	}

	private void InitializeVulkanFunctions()
	{
		IntPtr device = Graphics.VulkanDevice;
		if ( device == IntPtr.Zero ) return;

		try
		{
			vkCreateAccelerationStructureKHR = LoadFunction<vkCreateAccelerationStructureKHRDelegate>( device, "vkCreateAccelerationStructureKHR" );
			vkDestroyAccelerationStructureKHR = LoadFunction<vkDestroyAccelerationStructureKHRDelegate>( device, "vkDestroyAccelerationStructureKHR" );
			vkCmdBuildAccelerationStructuresKHR = LoadFunction<vkCmdBuildAccelerationStructuresKHRDelegate>( device, "vkCmdBuildAccelerationStructuresKHR" );
			vkGetAccelerationStructureBuildSizesKHR = LoadFunction<vkGetAccelerationStructureBuildSizesKHRDelegate>( device, "vkGetAccelerationStructureBuildSizesKHR" );
			vkGetAccelerationStructureDeviceAddressKHR = LoadFunction<vkGetAccelerationStructureDeviceAddressKHRDelegate>( device, "vkGetAccelerationStructureDeviceAddressKHR" );

			_initialized = true;
		}
		catch ( Exception e )
		{
			Log.Warning( $"Failed to initialize Vulkan Ray Tracing functions: {e.Message}" );
		}
	}

	private T LoadFunction<T>( IntPtr device, string name ) where T : Delegate
	{
		IntPtr addr = vkGetDeviceProcAddr( device, name );
		if ( addr == IntPtr.Zero ) throw new Exception( $"Could not find function {name}" );
		return Marshal.GetDelegateForFunctionPointer<T>( addr );
	}

	public override void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		if ( !_initialized ) return;

		// Maintain acceleration structures here
		UpdateAccelerationStructures();
	}

	private void UpdateAccelerationStructures()
	{
		// Logic to collect scene geometry and build/update BLAS and TLAS
		// This would typically involve iterating over Scene.SceneWorld.SceneObjects
	}

	/// <summary>
	/// Builds a Bottom-Level Acceleration Structure for the given geometry data.
	/// </summary>
	public ulong BuildBLAS( IntPtr vertexBuffer, uint vertexCount, IntPtr indexBuffer, uint indexCount )
	{
		if ( !_initialized ) return 0;

		// Placeholder for BLAS creation logic using vkCreateAccelerationStructureKHR and vkCmdBuildAccelerationStructuresKHR
		return 0;
	}

	/// <summary>
	/// Builds a Top-Level Acceleration Structure from a list of BLAS instances.
	/// </summary>
	public void BuildTLAS( IEnumerable<ulong> instances )
	{
		if ( !_initialized ) return;

		// Placeholder for TLAS creation logic
	}

	/// <summary>
	/// Gets the device address of an acceleration structure.
	/// </summary>
	public ulong GetDeviceAddress( ulong accelerationStructure )
	{
		if ( !_initialized ) return 0;

		var info = new VkAccelerationStructureDeviceAddressInfoKHR
		{
			sType = 1000150014, // VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR
			accelerationStructure = accelerationStructure
		};

		return vkGetAccelerationStructureDeviceAddressKHR( Graphics.VulkanDevice, ref info );
	}
}
