using System;
using System.Text;
using NativeEngine;

namespace Sandbox.Rendering;

/// <summary>
/// Procedural pass that incrementally updates Dazzle radiance cascades.
/// The resulting history texture is sampled by Dazzle lighting in the next frame.
/// </summary>
internal sealed class DazzleRadianceCascadeLayer : ProceduralRenderLayer
{
	private const int TraceBit_AddLayers = 1 << 0;
	private const int TraceBit_GIEnabled = 1 << 1;
	private const int TraceBit_TexturesReady = 1 << 2;
	private const int TraceBit_PublishedValid = 1 << 3;
	private const int TraceBit_OnRender = 1 << 4;
	private const int TraceBit_PassNear = 1 << 5;
	private const int TraceBit_PassFar = 1 << 6;
	private const int TraceBit_PassTemporal = 1 << 7;
	private const int TraceBit_HistoryValidBefore = 1 << 8;
	private const int TraceBit_HistoryValidAfter = 1 << 9;
	private const int TraceBit_Disabled = 1 << 10;
	private const int TraceBit_MissingTargets = 1 << 11;
	private const int TraceBit_DiagnosticFailures = 1 << 12;

	private const int DiagBufferLength = 128;
	private const int DiagSampleCapacity = 4;
	private const int DiagSampleStride = 8;
	private const int DiagIndexVersion = 0;
	private const int DiagIndexStageMask = 4;
	private const int DiagIndexTotalPixels = 5;
	private const int DiagIndexUpdatedPixels = 6;
	private const int DiagIndexInvalidRadiance = 7;
	private const int DiagIndexNaNValues = 8;
	private const int DiagIndexZeroCascade = 9;
	private const int DiagIndexPropagationFailures = 10;
	private const int DiagIndexMissingInputs = 11;
	private const int DiagIndexTemporalInstability = 12;
	private const int DiagIndexClampedValues = 13;
	private const int DiagIndexNearSampleCounter = 14;
	private const int DiagIndexFarSampleCounter = 15;
	private const int DiagIndexTemporalSampleCounter = 16;
	private const int DiagSamplesBaseNear = 24;
	private const int DiagSamplesBaseFar = DiagSamplesBaseNear + DiagSampleCapacity * DiagSampleStride;
	private const int DiagSamplesBaseTemporal = DiagSamplesBaseFar + DiagSampleCapacity * DiagSampleStride;

	private const uint DiagFlagInvalid = 1u << 0;
	private const uint DiagFlagMissingInput = 1u << 1;
	private const uint DiagFlagZeroCascade = 1u << 2;
	private const uint DiagFlagPropagationFailure = 1u << 3;
	private const uint DiagFlagTemporalInstability = 1u << 4;
	private const uint DiagFlagClamped = 1u << 5;
	private const uint DiagFlagSkippedUpdate = 1u << 6;
	private const uint DiagFlagNaN = 1u << 7;

	private static readonly ComputeShader CascadeShader = new( "common/Dazzle/dazzle_radiance_cascade_cs" );
	private static readonly uint[] DiagnosticClearData = new uint[DiagBufferLength];

	private RenderViewport _viewport;
	private Vector2Int _cascadeSize;
	private bool _enabled;

	private Texture _cascadeNear;
	private Texture _cascadeFar;
	private Texture _historyA;
	private Texture _historyB;

	private bool _readFromA = true;
	private bool _historyValid;
	private int _frameParity;
	private bool _traceEnabled;
	private bool _traceLog;
	private int _traceFlags;
	private int _publishedTraceFlags;
	private int _traceFrame;
	private int _publishedTraceFrame;
	private bool _diagnosticsEnabled;
	private bool _diagnosticsReadbackPending;
	private int _diagnosticsDroppedFrames;
	private GpuBuffer<uint> _diagnosticBuffer;

	public DazzleRadianceCascadeLayer()
	{
		Name = "Dazzle Radiance Cascades";
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

		_traceEnabled = attrs.GetBoolValue( "Dazzle_GIPipelineTrace", false );
		_traceLog = attrs.GetBoolValue( "Dazzle_GIPipelineTraceLog", false );
		_diagnosticsEnabled = _traceEnabled && !Application.IsRetail;

		// Preserve bits from PublishForShading which occurred before Setup
		int persistentFlags = _traceFlags & TraceBit_PublishedValid;
		_traceFlags = TraceBit_AddLayers | persistentFlags;

		if ( _diagnosticsEnabled )
		{
			EnsureDiagnosticBuffer();
		}
		else
		{
			ReleaseDiagnosticBuffer();
		}

		_enabled = attrs.GetBoolValue( "Dazzle_Enabled", false ) && attrs.GetBoolValue( "Dazzle_GIEnable", true );
		if ( _enabled )
			_traceFlags |= TraceBit_GIEnabled;

		if ( !_enabled )
		{
			_traceFlags |= TraceBit_Disabled;
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		float resolutionScale = attrs.GetFloatValue( "Dazzle_GIResolutionScale", 0.5f );
		EnsureTextures( resolutionScale );
		if ( _cascadeNear is not null && _historyA is not null )
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
		int nearIndex = _cascadeNear?.Index ?? 0;
		int farIndex = _cascadeFar?.Index ?? 0;
		int historyIndex = ReadHistoryTexture?.Index ?? 0;

		if ( !enabled )
		{
			attrs.SetIntValue( "Dazzle_GITextureIndex", 0 );
			attrs.SetBoolValue( "Dazzle_GIValid", false );
			traceFlags |= TraceBit_Disabled;
			attrs.SetIntValue( "Dazzle_GITraceFlags", traceFlags );
			attrs.SetIntValue( "Dazzle_GITraceFrame", _publishedTraceFrame );
			attrs.SetIntValue( "Dazzle_GITraceNearIndex", nearIndex );
			attrs.SetIntValue( "Dazzle_GITraceFarIndex", farIndex );
			attrs.SetIntValue( "Dazzle_GITraceHistoryIndex", historyIndex );
			return;
		}

		int textureIndex = (_historyValid && ReadHistoryTexture is { IsValid: true }) ? ReadHistoryTexture.Index : 0;
		attrs.SetIntValue( "Dazzle_GITextureIndex", textureIndex );
		attrs.SetBoolValue( "Dazzle_GIValid", textureIndex > 0 );
		if ( textureIndex > 0 )
		{
			traceFlags |= TraceBit_PublishedValid;
			_traceFlags |= TraceBit_PublishedValid;
		}

		attrs.SetIntValue( "Dazzle_GITraceFlags", traceFlags );
		attrs.SetIntValue( "Dazzle_GITraceFrame", _publishedTraceFrame );
		attrs.SetIntValue( "Dazzle_GITraceNearIndex", nearIndex );
		attrs.SetIntValue( "Dazzle_GITraceFarIndex", farIndex );
		attrs.SetIntValue( "Dazzle_GITraceHistoryIndex", historyIndex );
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

		if ( _cascadeNear is null || _cascadeFar is null )
		{
			_traceFlags |= TraceBit_MissingTargets;
			if ( _traceEnabled ) Log.Warning( "[DazzleGI] Tracing failed: Cascade textures are null." );
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		var readHistory = ReadHistoryTexture;
		var writeHistory = WriteHistoryTexture;
		if ( readHistory is null || writeHistory is null || !readHistory.IsValid || !writeHistory.IsValid )
		{
			_traceFlags |= TraceBit_MissingTargets;
			if ( _traceEnabled ) Log.Warning( $"[DazzleGI] Tracing failed: History textures invalid (Read: {readHistory?.ResourceName ?? "null"}, Write: {writeHistory?.ResourceName ?? "null"})." );
			PublishTraceState();
			MaybeLogTrace();
			return;
		}

		_traceFlags |= TraceBit_OnRender;
		if ( _historyValid )
			_traceFlags |= TraceBit_HistoryValidBefore;

		var attrs = RenderAttributes.Pool.Get();
		var frameTexture = Graphics.GrabFrameTexture( "DazzleInputColor", attrs, Graphics.DownsampleMethod.GaussianBlur );
		if ( frameTexture is null || frameTexture.ColorTarget is null || !frameTexture.ColorTarget.IsValid )
		{
			if ( _traceEnabled ) Log.Warning( "[DazzleGI] Tracing failed: GrabFrameTexture returned invalid target." );
			RenderAttributes.Pool.Return( attrs );
			return;
		}

		attrs.Set( "DazzleInputColor", frameTexture.ColorTarget );
		attrs.Set( "DazzleCascadeNear", _cascadeNear );
		attrs.Set( "DazzleCascadeFar", _cascadeFar );
		attrs.Set( "DazzleHistoryRadiance", readHistory );
		attrs.Set( "DazzleOutNear", _cascadeNear );
		attrs.Set( "DazzleOutFar", _cascadeFar );
		attrs.Set( "DazzleOutHistory", writeHistory );

		var fullWidth = Math.Max( (float)Graphics.Viewport.Width, 1.0f );
		var fullHeight = Math.Max( (float)Graphics.Viewport.Height, 1.0f );
		var invCascade = new Vector2( 1.0f / Math.Max( _cascadeSize.x, 1 ), 1.0f / Math.Max( _cascadeSize.y, 1 ) );
		var inputScale = new Vector2( fullWidth / Math.Max( _cascadeSize.x, 1 ), fullHeight / Math.Max( _cascadeSize.y, 1 ) );

		attrs.Set( "DazzleInvCascadeSize", invCascade );
		attrs.Set( "DazzleInputToCascadeScale", inputScale );
		attrs.Set( "DazzleFrameParity", _frameParity );
		attrs.Set( "Dazzle_GIUpdateFraction", Graphics.FrameAttributes.GetFloat( "Dazzle_GIUpdateFraction", 1.0f ) );
		attrs.Set( "Dazzle_GITemporalBlend", Graphics.FrameAttributes.GetFloat( "Dazzle_GITemporalBlend", 0.9f ) );
		attrs.Set( "Dazzle_GIBounceStrength", Graphics.FrameAttributes.GetFloat( "Dazzle_GIBounceStrength", 0.75f ) );
		attrs.Set( "Dazzle_MultiBounceInfluence", Graphics.FrameAttributes.GetFloat( "Dazzle_MultiBounceInfluence", 0.65f ) );
		attrs.Set( "Dazzle_ExposureCompensation", Graphics.FrameAttributes.GetFloat( "Dazzle_ExposureCompensation", 1.0f ) );
		attrs.Set( "Dazzle_WhitePoint", Graphics.FrameAttributes.GetFloat( "Dazzle_WhitePoint", 8.0f ) );
		attrs.Set( "Dazzle_TonemapShoulder", Graphics.FrameAttributes.GetFloat( "Dazzle_TonemapShoulder", 0.75f ) );
		attrs.Set( "DazzleDiagEnabled", _diagnosticsEnabled ? 1 : 0 );
		if ( _diagnosticsEnabled && _diagnosticBuffer is not null )
		{
			_diagnosticBuffer.SetData( DiagnosticClearData );
			attrs.Set( "DazzleDiagBuffer", _diagnosticBuffer );
		}

		if ( CascadeShader is null )
		{
			if ( _traceEnabled ) Log.Error( "[DazzleGI] CascadeShader is null!" );
			RenderAttributes.Pool.Return( attrs );
			return;
		}

		attrs.SetCombo( "D_PASS", 0 );
		CascadeShader.DispatchWithAttributes( attrs, _cascadeSize.x, _cascadeSize.y, 1 );
		_traceFlags |= TraceBit_PassNear;

		attrs.SetCombo( "D_PASS", 1 );
		CascadeShader.DispatchWithAttributes( attrs, _cascadeSize.x, _cascadeSize.y, 1 );
		_traceFlags |= TraceBit_PassFar;

		attrs.SetCombo( "D_PASS", 2 );
		CascadeShader.DispatchWithAttributes( attrs, _cascadeSize.x, _cascadeSize.y, 1 );
		_traceFlags |= TraceBit_PassTemporal;

		RenderAttributes.Pool.Return( attrs );

		_readFromA = !_readFromA;
		_historyValid = true;
		_frameParity = (_frameParity + 1) & 3;
		_traceFlags |= TraceBit_HistoryValidAfter;
		PublishTraceState( attrs.Get(), advanceFrame: true );
		MaybeLogTrace();
		RequestDiagnosticsReadback();
	}

	private Texture ReadHistoryTexture => _readFromA ? _historyA : _historyB;
	private Texture WriteHistoryTexture => _readFromA ? _historyB : _historyA;

	private void PublishTraceState( CRenderAttributes target = default, bool advanceFrame = false )
	{
		// Merge current frame flags with persistent bits from the previous publication
		_publishedTraceFlags = _traceFlags | (_publishedTraceFlags & TraceBit_DiagnosticFailures);
		_publishedTraceFrame = _traceFrame;

		if ( target.IsValid )
		{
			target.SetIntValue( "Dazzle_GITraceFlags", _publishedTraceFlags );
			target.SetIntValue( "Dazzle_GITraceFrame", _publishedTraceFrame );
			target.SetIntValue( "Dazzle_GITraceNearIndex", _cascadeNear?.Index ?? 0 );
			target.SetIntValue( "Dazzle_GITraceFarIndex", _cascadeFar?.Index ?? 0 );
			target.SetIntValue( "Dazzle_GITraceHistoryIndex", ReadHistoryTexture?.Index ?? 0 );
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

		// Log frequently if just starting or if frame parity aligns, otherwise throttle.
		bool forceLog = _publishedTraceFrame < 10 || (_publishedTraceFlags & TraceBit_DiagnosticFailures) != 0;
		if ( !forceLog && (_publishedTraceFrame % 60 != 0) )
			return;

		bool publishedValid = (_publishedTraceFlags & TraceBit_PublishedValid) != 0;
		Log.Info( $"[DazzleGI.Trace] frame={_publishedTraceFrame} flags=0x{_publishedTraceFlags:X} enabled={_enabled} historyValid={_historyValid} publishedValid={publishedValid} near={_cascadeNear?.Index ?? 0} far={_cascadeFar?.Index ?? 0} history={ReadHistoryTexture?.Index ?? 0}" );
	}

	private void EnsureTextures( float requestedScale )
	{
		requestedScale = Math.Clamp( requestedScale, 0.25f, 1.0f );

		int targetWidth = Math.Max( 64, (int)MathF.Round( _viewport.Rect.Width * requestedScale ) );
		int targetHeight = Math.Max( 64, (int)MathF.Round( _viewport.Rect.Height * requestedScale ) );

		var desiredSize = new Vector2Int( targetWidth, targetHeight );
		if ( _cascadeNear is not null && _cascadeNear.IsValid && _cascadeSize == desiredSize )
			return;

		ReleaseTextures();

		_cascadeNear = CreateRadianceTexture( "DazzleCascadeNear", targetWidth, targetHeight );
		_cascadeFar = CreateRadianceTexture( "DazzleCascadeFar", targetWidth, targetHeight );
		_historyA = CreateRadianceTexture( "DazzleCascadeHistoryA", targetWidth, targetHeight );
		_historyB = CreateRadianceTexture( "DazzleCascadeHistoryB", targetWidth, targetHeight );
		_cascadeSize = desiredSize;
		_historyValid = false;
		_readFromA = true;
	}

	private static Texture CreateRadianceTexture( string name, int width, int height )
	{
		return Texture.Create( width, height, ImageFormat.RGBA16161616F )
			.WithName( name )
			.WithUAVBinding()
			.Finish();
	}

	private void ReleaseTextures()
	{
		_cascadeNear?.Dispose();
		_cascadeFar?.Dispose();
		_historyA?.Dispose();
		_historyB?.Dispose();

		_cascadeNear = null;
		_cascadeFar = null;
		_historyA = null;
		_historyB = null;

		ReleaseDiagnosticBuffer();
	}

	private void EnsureDiagnosticBuffer()
	{
		if ( _diagnosticBuffer is { IsValid: true } )
			return;

		_diagnosticBuffer = new GpuBuffer<uint>( DiagBufferLength, GpuBuffer.UsageFlags.Structured, "DazzleGiDiagnostics" );
	}

	private void ReleaseDiagnosticBuffer()
	{
		_diagnosticBuffer?.Dispose();
		_diagnosticBuffer = null;
		_diagnosticsReadbackPending = false;
		_diagnosticsDroppedFrames = 0;
	}

	private void RequestDiagnosticsReadback()
	{
		if ( !_diagnosticsEnabled || _diagnosticBuffer is null )
			return;

		if ( _diagnosticsReadbackPending )
		{
			_diagnosticsDroppedFrames++;
			return;
		}

		_diagnosticsReadbackPending = true;
		int traceFrame = _publishedTraceFrame;
		bool verbose = _traceLog;
		int droppedFrames = _diagnosticsDroppedFrames;
		_diagnosticsDroppedFrames = 0;

		_diagnosticBuffer.GetDataAsync( data =>
		{
			var snapshot = new uint[DiagBufferLength];
			int count = Math.Min( data.Length, snapshot.Length );
			data[..count].CopyTo( snapshot );

			MainThread.Queue( () =>
			{
				_diagnosticsReadbackPending = false;
				ProcessDiagnosticSnapshot( snapshot, traceFrame, verbose, droppedFrames );
			} );
		} );
	}

	private void ProcessDiagnosticSnapshot( uint[] data, int traceFrame, bool verbose, int droppedFrames )
	{
		if ( data is null || data.Length < DiagBufferLength || data[DiagIndexVersion] == 0 )
			return;

		uint stageMask = data[DiagIndexStageMask];
		uint totalPixels = data[DiagIndexTotalPixels];
		uint updatedPixels = data[DiagIndexUpdatedPixels];
		uint invalidRadiance = data[DiagIndexInvalidRadiance];
		uint nanValues = data[DiagIndexNaNValues];
		uint zeroCascade = data[DiagIndexZeroCascade];
		uint propagationFailures = data[DiagIndexPropagationFailures];
		uint missingInputs = data[DiagIndexMissingInputs];
		uint temporalInstability = data[DiagIndexTemporalInstability];
		uint clampedValues = data[DiagIndexClampedValues];

		bool hasErrors =
			invalidRadiance > 0 ||
			nanValues > 0 ||
			zeroCascade > 0 ||
			propagationFailures > 0 ||
			missingInputs > 0 ||
			temporalInstability > 0;

		if ( hasErrors )
		{
			_traceFlags |= TraceBit_DiagnosticFailures;
			_publishedTraceFlags |= TraceBit_DiagnosticFailures;
		}

		Log.Info(
			$"[DazzleGI.Diagnostic][Summary] frame={traceFrame} stageMask=0x{stageMask:X} pixels={updatedPixels}/{totalPixels} " +
			$"invalid={invalidRadiance} nan={nanValues} zero={zeroCascade} propagation={propagationFailures} " +
			$"missingInputs={missingInputs} temporalInstability={temporalInstability} clamped={clampedValues} droppedReadbacks={droppedFrames}" );

		if ( !verbose && !hasErrors )
			return;

		LogDiagnosticSamples( data, "Near", DiagIndexNearSampleCounter, DiagSamplesBaseNear, traceFrame );
		LogDiagnosticSamples( data, "Far", DiagIndexFarSampleCounter, DiagSamplesBaseFar, traceFrame );
		LogDiagnosticSamples( data, "Temporal", DiagIndexTemporalSampleCounter, DiagSamplesBaseTemporal, traceFrame );
	}

	private static void LogDiagnosticSamples( uint[] data, string stageName, int counterIndex, int baseIndex, int traceFrame )
	{
		int sampleCount = Math.Min( (int)data[counterIndex], DiagSampleCapacity );
		for ( int i = 0; i < sampleCount; i++ )
		{
			int offset = baseIndex + i * DiagSampleStride;
			if ( offset + DiagSampleStride > data.Length )
				return;

			uint packedCell = data[offset + 0];
			int x = (int)(packedCell & 0xFFFF);
			int y = (int)((packedCell >> 16) & 0xFFFF);
			uint flags = data[offset + 1];
			float m0 = BitConverter.UInt32BitsToSingle( data[offset + 2] );
			float m1 = BitConverter.UInt32BitsToSingle( data[offset + 3] );
			float m2 = BitConverter.UInt32BitsToSingle( data[offset + 4] );
			float m3 = BitConverter.UInt32BitsToSingle( data[offset + 5] );
			float m4 = BitConverter.UInt32BitsToSingle( data[offset + 6] );
			float m5 = BitConverter.UInt32BitsToSingle( data[offset + 7] );

			string metrics = stageName switch
			{
				"Near" => $"ao={m0:0.000} depth={m1:0.0000} normalLen={m2:0.000} sceneLuma={m3:0.000} nearEnergy={m4:0.000} energyBoost={m5:0.000}",
				"Far" => $"centerEnergy={m0:0.000} neighborhoodEnergy={m1:0.000} farEnergy={m2:0.000} bounce={m3:0.000}",
				_ => $"currentEnergy={m0:0.000} historyEnergy={m1:0.000} resolvedEnergy={m2:0.000} temporalBlend={m3:0.000} reactive={m4:0.000} delta={m5:0.000}"
			};

			Log.Info( $"[DazzleGI.Diagnostic][{stageName}][Frame {traceFrame}][Cell {x},{y}] flags={FormatDiagFlags( flags )} {metrics}" );
		}
	}

	private static string FormatDiagFlags( uint flags )
	{
		if ( flags == 0 )
			return "none";

		var sb = new StringBuilder( 96 );

		void AppendFlag( uint bit, string name )
		{
			if ( (flags & bit) == 0 )
				return;

			if ( sb.Length > 0 )
				sb.Append( '|' );

			sb.Append( name );
		}

		AppendFlag( DiagFlagInvalid, "Invalid" );
		AppendFlag( DiagFlagMissingInput, "MissingInput" );
		AppendFlag( DiagFlagZeroCascade, "ZeroCascade" );
		AppendFlag( DiagFlagPropagationFailure, "PropagationFailure" );
		AppendFlag( DiagFlagTemporalInstability, "TemporalInstability" );
		AppendFlag( DiagFlagClamped, "Clamped" );
		AppendFlag( DiagFlagSkippedUpdate, "SkippedUpdate" );
		AppendFlag( DiagFlagNaN, "NaN" );
		return sb.ToString();
	}
}
