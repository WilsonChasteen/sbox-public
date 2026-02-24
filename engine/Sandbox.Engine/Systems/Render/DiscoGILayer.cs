using System;
using System.Text;
using NativeEngine;

namespace Sandbox.Rendering;

/// <summary>
/// Procedural pass that incrementally updates DISCO GI radiance fields.
/// The resulting history texture is sampled by the core lighting passes.
/// </summary>
internal sealed class DiscoGILayer : ProceduralRenderLayer
{
	private const int TraceBit_AddLayers = 1 << 0;
	private const int TraceBit_GIEnabled = 1 << 1;
	private const int TraceBit_TexturesReady = 1 << 2;
	private const int TraceBit_PublishedValid = 1 << 3;
	private const int TraceBit_OnRender = 1 << 4;
	private const int TraceBit_PassUpdate = 1 << 5;
	private const int TraceBit_PassPropagation = 1 << 6;
	private const int TraceBit_PassTemporal = 1 << 7;
	private const int TraceBit_HistoryValidBefore = 1 << 8;
	private const int TraceBit_HistoryValidAfter = 1 << 9;
	private const int TraceBit_Disabled = 1 << 10;
	private const int TraceBit_MissingTargets = 1 << 11;
	private const int TraceBit_DiagnosticFailures = 1 << 12;

	private const int DiagStageCount = 8;
	private const int DiagMetricsPerStage = 4;
	private const int DiagBufferElementCount = DiagStageCount * DiagMetricsPerStage;
	private static readonly uint[] DiagnosticClearData = new uint[DiagBufferElementCount];

	private static readonly ComputeShader DiscoComputeShader = new( "disco_gi/disco_gi_cs" );

	private RenderViewport _viewport;
	private Vector2Int _resolution;
	private bool _enabled;

	private Texture _radianceAccumulation;
	private Texture _spatialCache;
	private Texture _historyA;
	private Texture _historyB;
	private GpuBuffer<uint> _diagnosticBuffer;

	private bool _readFromA = true;
	private bool _historyValid;
	private int _frameParity;
	private bool _traceEnabled;
	private bool _traceLog;
	private int _traceFlags;
	private int _publishedTraceFlags;
	private int _traceFrame;
	private int _publishedTraceFrame;
	private int _debugView;
	private float _updateFraction = 1.0f;
	private float _temporalBlend = 0.9f;
	private float _bounceStrength = 0.75f;

	public DiscoGILayer()
	{
		Name = "DISCO Global Illumination";
		Flags |= LayerFlags.NeverRemove;
		Flags |= LayerFlags.DoesntModifyColorBuffers;
		Flags |= LayerFlags.DoesntModifyDepthStencilBuffer;
	}

	public void Setup( ISceneView view, RenderViewport viewport )
	{
		if ( !view.IsValid ) return;
		_viewport = viewport;

		var attrs = view.GetRenderAttributesPtr();
		if ( !attrs.IsValid ) return;

		_traceEnabled = attrs.GetBoolValue( "DiscoGI_PipelineTrace", false );
		_traceLog = attrs.GetBoolValue( "DiscoGI_PipelineTraceLog", false );

		int persistentFlags = _traceFlags & TraceBit_PublishedValid;
		_traceFlags = TraceBit_AddLayers | persistentFlags;

		_enabled = attrs.GetBoolValue( "DiscoGI_Enabled", false );
		_debugView = attrs.GetIntValue( "DiscoGI_DebugView", 0 );
		_updateFraction = attrs.GetFloatValue( "DiscoGI_UpdateFraction", 1.0f );
		_temporalBlend = attrs.GetFloatValue( "DiscoGI_TemporalBlend", 0.9f );
		_bounceStrength = attrs.GetFloatValue( "DiscoGI_BounceStrength", 0.75f );
		if ( _enabled )
			_traceFlags |= TraceBit_GIEnabled;

		if ( !_enabled )
		{
			_traceFlags |= TraceBit_Disabled;
			PublishTraceState(attrs);
			MaybeLogTrace();
			return;
		}

		float resolutionScale = attrs.GetFloatValue( "DiscoGI_ResolutionScale", 0.5f );
		EnsureTextures( resolutionScale );
		if ( _radianceAccumulation is not null && _historyA is not null )
		{
			_traceFlags |= TraceBit_TexturesReady;
		}
		else
		{
			_traceFlags |= TraceBit_MissingTargets;
		}

		PublishTraceState( attrs );
	}

	public void PublishForShading( ISceneView view, bool enabled )
	{
		if ( !view.IsValid ) return;
		var attrs = view.GetRenderAttributesPtr();
		if ( !attrs.IsValid ) return;

		int traceFlags = _publishedTraceFlags;
		
		if ( !enabled )
		{
			attrs.SetIntValue( "DiscoGI_TextureIndex", 0 );
			attrs.SetBoolValue( "DiscoGI_Valid", false );
			traceFlags |= TraceBit_Disabled;
			attrs.SetIntValue( "DiscoGI_TraceFlags", traceFlags );
			return;
		}

		int textureIndex = 0;
		if ( _historyValid )
		{
			// Debug views 3/4 are exposed as "Near/Far Cascade" in the component.
			// Publish our intermediate buffers so those views don't alias history.
			if ( _debugView == 3 && _spatialCache is { IsValid: true } )
			{
				textureIndex = _spatialCache.Index;
			}
			else if ( _debugView == 4 && _radianceAccumulation is { IsValid: true } )
			{
				textureIndex = _radianceAccumulation.Index;
			}
			else if ( ReadHistoryTexture is { IsValid: true } history )
			{
				textureIndex = history.Index;
			}
		}

		attrs.SetIntValue( "DiscoGI_TextureIndex", textureIndex );
		attrs.SetBoolValue( "DiscoGI_Valid", textureIndex > 0 );
		if ( textureIndex > 0 )
		{
			traceFlags |= TraceBit_PublishedValid;
			_traceFlags |= TraceBit_PublishedValid;
		}

		attrs.SetIntValue( "DiscoGI_TraceFlags", traceFlags );
		_publishedTraceFlags = traceFlags;
	}

	internal override void OnRender()
	{
		if ( !_enabled )
		{
			_traceFlags |= TraceBit_Disabled;
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		if ( _radianceAccumulation is null || _spatialCache is null )
		{
			_traceFlags |= TraceBit_MissingTargets;
			if ( _traceEnabled ) Log.Warning( "[DiscoGI] Tracing failed: Accumulation textures are null." );
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		var readHistory = ReadHistoryTexture;
		var writeHistory = WriteHistoryTexture;
		if ( readHistory is null || writeHistory is null || !readHistory.IsValid || !writeHistory.IsValid )
		{
			_traceFlags |= TraceBit_MissingTargets;
			if ( _traceEnabled ) Log.Warning( $"[DiscoGI] Tracing failed: History textures invalid." );
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		_traceFlags |= TraceBit_OnRender;
		if ( _historyValid )
			_traceFlags |= TraceBit_HistoryValidBefore;

		var attrs = RenderAttributes.Pool.Get();
		var colorTarget = Graphics.SceneLayer.GetColorTarget();
		try
		{
			Graphics.Attributes.MergeTo( attrs );

			bool hasInputColor = false;
			if ( !colorTarget.IsNull && colorTarget.IsStrongHandleValid() )
			{
				attrs.Set( "DiscoGI_InputColor", colorTarget );
				hasInputColor = true;
			}

			if ( !hasInputColor )
			{
				var frameTexture = Graphics.GrabFrameTexture( "DiscoInputColor", attrs, Graphics.DownsampleMethod.GaussianBlur );
				if ( frameTexture is not null && frameTexture.ColorTarget is { IsValid: true } frameColor )
				{
					attrs.Set( "DiscoGI_InputColor", frameColor );
					hasInputColor = true;
				}
			}

			if ( !hasInputColor )
			{
				if ( _traceEnabled ) Log.Warning( "[DiscoGI] Tracing failed: no valid scene color input texture." );
				return;
			}

			attrs.Set( "DiscoGI_History", readHistory ); // SRV for Pass 0
			
			var fullWidth = Math.Max( (float)Graphics.Viewport.Width, 1.0f );
			var fullHeight = Math.Max( (float)Graphics.Viewport.Height, 1.0f );
			var invRes = new Vector2( 1.0f / Math.Max( _resolution.x, 1 ), 1.0f / Math.Max( _resolution.y, 1 ) );
			var inputScale = new Vector2( fullWidth / Math.Max( _resolution.x, 1 ), fullHeight / Math.Max( _resolution.y, 1 ) );

			attrs.Set( "DiscoGI_InvResolution", invRes );
			attrs.Set( "DiscoGI_InputScale", inputScale );
			attrs.Set( "DiscoGI_FrameParity", _frameParity );
			attrs.Set( "DiscoGI_UpdateFraction", _updateFraction );
			attrs.Set( "DiscoGI_TemporalBlend", _temporalBlend );
			attrs.Set( "DiscoGI_BounceStrength", _bounceStrength );

			if ( DiscoComputeShader is null )
			{
				if ( _traceEnabled ) Log.Error( "[DiscoGI] ComputeShader is null!" );
				return;
			}

			// Pass 0: Initial Screen-Space Raymarching / Radiance Collection
			attrs.Set( "DiscoGI_OutAccumulation", _radianceAccumulation );
			attrs.SetCombo( "D_PASS", 0 );
			DiscoComputeShader.DispatchWithAttributes( attrs, _resolution.x, _resolution.y, 1 );
			_traceFlags |= TraceBit_PassUpdate;

			// Pass 1: Spatial Filtering & Propagation
			attrs.Set( "DiscoGI_OutAccumulation", (Texture)null );
			attrs.Set( "DiscoGI_RadianceAccumulation", _radianceAccumulation );
			attrs.Set( "DiscoGI_OutSpatial", _spatialCache );
			attrs.SetCombo( "D_PASS", 1 );
			DiscoComputeShader.DispatchWithAttributes( attrs, _resolution.x, _resolution.y, 1 );
			_traceFlags |= TraceBit_PassPropagation;

			// Pass 2: Temporal Reprojection & Resolve
			attrs.Set( "DiscoGI_OutSpatial", (Texture)null );
			attrs.Set( "DiscoGI_SpatialCache", _spatialCache );
			attrs.Set( "DiscoGI_OutHistory", writeHistory );
			attrs.SetCombo( "D_PASS", 2 );
			DiscoComputeShader.DispatchWithAttributes( attrs, _resolution.x, _resolution.y, 1 );
			_traceFlags |= TraceBit_PassTemporal;

			attrs.Set( "DiscoGI_OutHistory", (Texture)null );
			RunDiagnostics( attrs, writeHistory );
			var traceTarget = attrs.Get();

			_readFromA = !_readFromA;
			_historyValid = true;
			_frameParity = (_frameParity + 1) & 3;
			_traceFlags |= TraceBit_HistoryValidAfter;
			PublishTraceState( traceTarget, advanceFrame: true );
			MaybeLogTrace();
		}
		finally
		{
			if ( !colorTarget.IsNull )
			{
				colorTarget.DestroyStrongHandle();
			}

			RenderAttributes.Pool.Return( attrs );
		}
	}

	private Texture ReadHistoryTexture => _readFromA ? _historyA : _historyB;
	private Texture WriteHistoryTexture => _readFromA ? _historyB : _historyA;

	private void PublishTraceState( CRenderAttributes target = default, bool advanceFrame = false )
	{
		_publishedTraceFlags = _traceFlags | (_publishedTraceFlags & TraceBit_DiagnosticFailures);
		_publishedTraceFrame = _traceFrame;

		if ( target.IsValid )
		{
			target.SetIntValue( "DiscoGI_TraceFlags", _publishedTraceFlags );
		}

		if ( advanceFrame )
		{
			_traceFrame++;
		}
	}

	private void MaybeLogTrace()
	{
		if ( !_traceEnabled || !_traceLog )
			return;

		bool forceLog = _publishedTraceFrame < 10 || (_publishedTraceFlags & TraceBit_DiagnosticFailures) != 0;
		if ( !forceLog && (_publishedTraceFrame % 60 != 0) )
			return;

		bool publishedValid = (_publishedTraceFlags & TraceBit_PublishedValid) != 0;
		Log.Info( $"[DiscoGI.Trace] frame={_publishedTraceFrame} flags=0x{_publishedTraceFlags:X} enabled={_enabled} historyValid={_historyValid} publishedValid={publishedValid}" );
	}

	private void RunDiagnostics( RenderAttributes attrs, Texture writeHistory )
	{
		if ( !_traceEnabled || !_traceLog || _diagnosticBuffer is null )
			return;

		_diagnosticBuffer.SetData( DiagnosticClearData.AsSpan() );
		Graphics.ResourceBarrierTransition( _diagnosticBuffer, ResourceState.UnorderedAccess );

		DispatchDiagnosticStage( attrs, _radianceAccumulation, 0 );
		DispatchDiagnosticStage( attrs, _spatialCache, 1 );
		DispatchDiagnosticStage( attrs, writeHistory, 2 );
		DispatchDiagnosticTerm( attrs, 3, 1 );
		DispatchDiagnosticTerm( attrs, 4, 2 );
		DispatchDiagnosticTerm( attrs, 5, 3 );
		DispatchDiagnosticTerm( attrs, 6, 4 );
		DispatchDiagnosticTerm( attrs, 7, 5 );

		Graphics.ResourceBarrierTransition( _diagnosticBuffer, ResourceState.GenericRead );

		Span<uint> metrics = stackalloc uint[DiagBufferElementCount];
		_diagnosticBuffer.GetData( metrics );
		LogDiagnosticSummary( metrics );
	}

	private void DispatchDiagnosticStage( RenderAttributes attrs, Texture stageTexture, int stageIndex )
	{
		if ( stageTexture is null || !stageTexture.IsValid )
			return;

		attrs.Set( "DiscoGI_DiagInput", stageTexture );
		attrs.Set( "DiscoGI_DiagBuffer", _diagnosticBuffer );
		attrs.Set( "DiscoGI_DiagStage", stageIndex );
		attrs.Set( "DiscoGI_DiagMode", 0 );
		attrs.SetCombo( "D_PASS", 3 );
		DiscoComputeShader.DispatchWithAttributes( attrs, _resolution.x, _resolution.y, 1 );
	}

	private void DispatchDiagnosticTerm( RenderAttributes attrs, int stageIndex, int diagMode )
	{
		attrs.Set( "DiscoGI_DiagBuffer", _diagnosticBuffer );
		attrs.Set( "DiscoGI_DiagStage", stageIndex );
		attrs.Set( "DiscoGI_DiagMode", diagMode );
		attrs.SetCombo( "D_PASS", 3 );
		DiscoComputeShader.DispatchWithAttributes( attrs, _resolution.x, _resolution.y, 1 );
	}

	private void LogDiagnosticSummary( ReadOnlySpan<uint> metrics )
	{
		LogStageDiagnostics( "Accumulation", metrics, 0 );
		LogStageDiagnostics( "Spatial", metrics, 1 );
		LogStageDiagnostics( "HistoryWrite", metrics, 2 );
		LogStageDiagnostics( "InputColorLuma", metrics, 3 );
		LogStageDiagnostics( "NormalFacing", metrics, 4 );
		LogStageDiagnostics( "DepthAttenuation", metrics, 5 );
		LogStageDiagnostics( "AOAttenuation", metrics, 6 );
		LogStageDiagnostics( "EnergyBoost", metrics, 7 );
	}

	private static void LogStageDiagnostics( string stageName, ReadOnlySpan<uint> metrics, int stageIndex )
	{
		int offset = stageIndex * DiagMetricsPerStage;
		uint sampleCount = metrics[offset + 0];
		uint nonZeroCount = metrics[offset + 1];
		uint sumLumaScaled = metrics[offset + 2];
		uint maxLumaScaled = metrics[offset + 3];

		float avgLuma = sampleCount > 0 ? (sumLumaScaled / 1024.0f) / sampleCount : 0.0f;
		float maxLuma = maxLumaScaled / 1024.0f;
		bool blank = nonZeroCount == 0 || maxLuma <= 1e-5f;

		Log.Info( $"[DiscoGI.Diag] stage={stageName} samples={sampleCount} nonZero={nonZeroCount} avgLuma={avgLuma:0.000000} maxLuma={maxLuma:0.000000} blank={blank}" );
	}

	private void EnsureTextures( float requestedScale )
	{
		requestedScale = Math.Clamp( requestedScale, 0.25f, 1.0f );

		int targetWidth = Math.Max( 64, (int)MathF.Round( _viewport.Rect.Width * requestedScale ) );
		int targetHeight = Math.Max( 64, (int)MathF.Round( _viewport.Rect.Height * requestedScale ) );

		var desiredSize = new Vector2Int( targetWidth, targetHeight );
		if ( _radianceAccumulation is not null && _radianceAccumulation.IsValid && _resolution == desiredSize )
			return;

		ReleaseTextures();

		_radianceAccumulation = CreateRadianceTexture( "DiscoGI_Accum", targetWidth, targetHeight );
		_spatialCache = CreateRadianceTexture( "DiscoGI_Spatial", targetWidth, targetHeight );
		_historyA = CreateRadianceTexture( "DiscoGI_HistoryA", targetWidth, targetHeight );
		_historyB = CreateRadianceTexture( "DiscoGI_HistoryB", targetWidth, targetHeight );
		_diagnosticBuffer ??= new GpuBuffer<uint>( DiagBufferElementCount, debugName: "DiscoGI_Diagnostics" );
		_resolution = desiredSize;
		_historyValid = false;
		_readFromA = true;
	}

	private static Texture CreateRadianceTexture( string name, int width, int height )
	{
		return Texture.CreateRenderTarget()
			.WithFormat( ImageFormat.RGBA16161616F )
			.WithSize( width, height )
			.WithUAVBinding()
			.Create( name );
	}

	private void ReleaseTextures()
	{
		_radianceAccumulation?.Dispose();
		_spatialCache?.Dispose();
		_historyA?.Dispose();
		_historyB?.Dispose();
		_diagnosticBuffer?.Dispose();

		_radianceAccumulation = null;
		_spatialCache = null;
		_historyA = null;
		_historyB = null;
		_diagnosticBuffer = null;
	}
}
