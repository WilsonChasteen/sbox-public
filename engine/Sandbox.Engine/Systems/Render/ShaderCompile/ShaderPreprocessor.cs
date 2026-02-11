using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Sandbox.Engine.Shaders;

class ShaderPreprocessor
{
	ShaderPreprocessorOptions Options { get; set; }
	List<string> IncludedFiles = new();

	public ShaderPreprocessor( ShaderPreprocessorOptions options )
	{
		Options = options;
	}

	static string NormalizePath( string path )
	{
		if ( string.IsNullOrWhiteSpace( path ) )
			return string.Empty;

		var parts = path.Replace( '\\', '/' ).Split( '/', StringSplitOptions.RemoveEmptyEntries );
		var normalizedParts = new List<string>( parts.Length );

		foreach ( var part in parts )
		{
			if ( part == "." )
				continue;

			if ( part == ".." )
			{
				if ( normalizedParts.Count > 0 )
					normalizedParts.RemoveAt( normalizedParts.Count - 1 );

				continue;
			}

			normalizedParts.Add( part );
		}

		return string.Join( '/', normalizedParts );
	}

	static string ParentDirectory( string path )
	{
		if ( string.IsNullOrEmpty( path ) )
			return string.Empty;

		var idx = path.LastIndexOf( '/' );
		if ( idx <= 0 )
			return string.Empty;

		return path[..idx];
	}

	IEnumerable<string> GetIncludeCandidates( string includeFile, string parentFile )
	{
		var candidates = new List<string>();
		var seen = new HashSet<string>( StringComparer.OrdinalIgnoreCase );

		void AddCandidate( string candidate )
		{
			var normalized = NormalizePath( candidate );
			if ( string.IsNullOrWhiteSpace( normalized ) )
				return;

			if ( seen.Add( normalized ) )
				candidates.Add( normalized );
		}

		includeFile = NormalizePath( includeFile );
		var parentDir = NormalizePath( Path.GetDirectoryName( parentFile ) ?? string.Empty );

		// Standard behavior: include relative to the current file.
		if ( !string.IsNullOrEmpty( parentDir ) )
		{
			AddCandidate( $"{parentDir}/{includeFile}" );
		}

		// Legacy behavior: include from global shader root.
		AddCandidate( includeFile );
		AddCandidate( $"shaders/{includeFile}" );

		// Fallback for non-standard relative paths from nested includes:
		// walk parent directories and try resolving include at each level.
		var searchDir = parentDir;
		while ( !string.IsNullOrEmpty( searchDir ) )
		{
			AddCandidate( $"{searchDir}/{includeFile}" );
			searchDir = ParentDirectory( searchDir );
		}

		// Common legacy RTXGI include prefix used inside imported SDK files.
		if ( includeFile.StartsWith( "include/", StringComparison.OrdinalIgnoreCase ) )
		{
			var suffix = includeFile["include/".Length..];
			AddCandidate( $"common/rtxgi/ddgi/include/{suffix}" );
		}

		// Legacy relative header paths from SDK include files.
		const string rtxgiRelativePrefix = "../../../include/rtxgi/";
		if ( includeFile.StartsWith( rtxgiRelativePrefix, StringComparison.OrdinalIgnoreCase ) )
		{
			var suffix = includeFile[rtxgiRelativePrefix.Length..];
			AddCandidate( $"common/thirdparty/rtxgi/shaders/rtxgi/{suffix}" );
			AddCandidate( $"common/thirdparty/rtxgi-ddgi/rtxgi-sdk/include/rtxgi/{suffix}" );
		}

		// Global include tree fallback for include/rtxgi/*.h paths.
		const string rtxgiIncludePrefix = "include/rtxgi/";
		if ( includeFile.StartsWith( rtxgiIncludePrefix, StringComparison.OrdinalIgnoreCase ) )
		{
			var suffix = includeFile[rtxgiIncludePrefix.Length..];
			AddCandidate( $"common/thirdparty/rtxgi/shaders/rtxgi/{suffix}" );
			AddCandidate( $"common/thirdparty/rtxgi-ddgi/rtxgi-sdk/include/rtxgi/{suffix}" );
		}

		return candidates;
	}

	bool HandleInclude( string includeFile, string parentFile, out string includeContents )
	{
		includeContents = string.Empty;

		string path = null;
		foreach ( var candidate in GetIncludeCandidates( includeFile, parentFile ) )
		{
			if ( ShaderCompile.FileSystem.FileExists( candidate ) )
			{
				path = candidate;
				break;
			}
		}

		if ( path is null )
		{
			return false;
		}

		bool coreContent = EngineFileSystem.CoreContent.FileExists( path );
		if ( coreContent && Options.IgnoreCoreIncludes )
		{
			return false;
		}

		// Already included, handle it with an empty string out
		if ( IncludedFiles.Any( x => x.Equals( path, StringComparison.OrdinalIgnoreCase ) ) )
		{
			return true;
		}

		// Open the file somehow
		string source = ShaderCompile.FileSystem.ReadAllText( path );
		includeContents = Preprocess( source, ShaderCompile.FileSystem.GetFullPath( path ), path );

		IncludedFiles.Add( path );

		return true;
	}

	Regex IncludePattern = new Regex( "#include \"([^>]+)\"", RegexOptions.Compiled );

	public string Preprocess( string source, string absolutePath, string relativePath )
	{
		var reader = new StringReader( source );
		var builder = new StringBuilder();

		// Add a header to the source
		builder.AppendLine( $"#line 1 \"{relativePath.Replace( "\\", "/" )}\"" );
		builder.AppendLine( "#include \"system.fxc\"" );

		string line;
		while ( (line = reader.ReadLine()) != null )
		{
			var match = IncludePattern.Match( line );
			if ( !Options.ExpandIncludes || !match.Success )
			{
				builder = builder.AppendLine( line );
				continue;
			}

			var file = match.Groups[1].Value;

			if ( HandleInclude( file, relativePath, out var includeContents ) )
			{
				builder.AppendLine( includeContents );
				continue;
			}

			builder = builder.AppendLine( line );
		}

		return builder.ToString();
	}
}
