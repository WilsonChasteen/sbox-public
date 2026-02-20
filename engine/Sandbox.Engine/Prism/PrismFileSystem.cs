using Sandbox;
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using Zio;
using Zio.FileSystems;

#nullable enable

namespace Sandbox.Prism;

/// <summary>
/// A shadow filesystem that intercepts shader files and injects Prism code.
/// </summary>
public sealed class PrismFileSystem : BaseFileSystem
{
	public PrismFileSystem() : base( new PrismInternalFileSystem() )
	{
	}
}

internal class PrismInternalFileSystem : Zio.FileSystems.FileSystem
{
	// We only intercept specific extensions
	private static readonly string[] InterceptExtensions = { ".shader", ".vfx" };

	private bool ShouldIntercept( UPath path )
	{
		var ext = path.GetExtensionWithDot();
		return InterceptExtensions.Contains( ext, StringComparer.OrdinalIgnoreCase );
	}

	// Helper to find the file in other filesystems
	// Helper to find the file in other filesystems
	// Unused method removed to fix nullability errors
    
    // ThreadStatic recursion guard
    
    // ThreadStatic recursion guard
    [ThreadStatic]
    private static bool _isIntercepting;

	protected override void CreateDirectoryImpl( UPath path ) { throw new UnauthorizedAccessException(); }
	protected override void DeleteDirectoryImpl( UPath path, bool isRecursive ) { throw new UnauthorizedAccessException(); }
	protected override void DeleteFileImpl( UPath path ) { throw new UnauthorizedAccessException(); }
	protected override FileAttributes GetAttributesImpl( UPath path ) 
	{
        // Simple passthrough or fake
        if ( ShouldIntercept( path ) )
        {
             // Check if it exists in original
             if ( ExistsInOriginal( path ) ) return FileAttributes.Normal;
        }
        throw new FileNotFoundException( path.FullName );
    }
	
	protected override long GetFileLengthImpl( UPath path )
    {
         if ( ShouldIntercept( path ) )
         {
             // This is expensive as we might need to read the patched content to know size
             using var s = OpenFileImpl( path, FileMode.Open, FileAccess.Read, FileShare.Read );
             return s.Length;
         }
         throw new FileNotFoundException( path.FullName );
    }

	protected override void MoveDirectoryImpl( UPath srcPath, UPath destPath ) { throw new UnauthorizedAccessException(); }
	protected override void MoveFileImpl( UPath srcPath, UPath destPath ) { throw new UnauthorizedAccessException(); }
	
	protected override Stream OpenFileImpl( UPath path, FileMode mode, FileAccess access, FileShare share )
	{
		if ( mode != FileMode.Open || access != FileAccess.Read ) throw new UnauthorizedAccessException();
		if ( !ShouldIntercept( path ) ) throw new FileNotFoundException( path.FullName );
        
        if ( _isIntercepting ) throw new FileNotFoundException( path.FullName );

        try
        {
            _isIntercepting = true;
            
            // Try to open from mounted
            var stream = FileSystem.Mounted?.OpenRead( path.FullName );
            if ( stream == null ) throw new FileNotFoundException( path.FullName );
            
            // Patch logic
            return PatchShader( stream );
        }
        catch ( Exception )
        {
            throw new FileNotFoundException( path.FullName );
        }
        finally
        {
            _isIntercepting = false;
        }
	}

    private Stream PatchShader( Stream source )
    {
        return ShaderPatcher.Patch( source );
    }

    private bool ExistsInOriginal( UPath path )
    {
        if ( _isIntercepting ) return false;
        try
        {
            _isIntercepting = true;
            return FileSystem.Mounted?.FileExists( path.FullName ) ?? false;
        }
        finally
        {
            _isIntercepting = false;
        }
    }

	protected override void ReplaceFileImpl( UPath srcPath, UPath destPath, UPath destBackupPath, bool ignoreMetadataErrors ) { throw new UnauthorizedAccessException(); }
	protected override void SetAttributesImpl( UPath path, FileAttributes attributes ) { throw new UnauthorizedAccessException(); }
	protected override void SetCreationTimeImpl( UPath path, DateTime time ) { throw new UnauthorizedAccessException(); }
	protected override void SetLastAccessTimeImpl( UPath path, DateTime time ) { throw new UnauthorizedAccessException(); }
	protected override void SetLastWriteTimeImpl( UPath path, DateTime time ) { throw new UnauthorizedAccessException(); }

	// Directories
	protected override bool DirectoryExistsImpl( UPath path ) { return false; }
    protected override IEnumerable<UPath> EnumeratePathsImpl( UPath path, string searchPattern, SearchOption searchOption, SearchTarget searchTarget ) { return Enumerable.Empty<UPath>(); }
    protected override bool FileExistsImpl( UPath path ) 
    {
        return ShouldIntercept( path ) && ExistsInOriginal( path );
    }

#nullable enable

	// Missing abstract members implementation
	protected override void CopyFileImpl( UPath srcPath, UPath destPath, bool overwrite ) { throw new UnauthorizedAccessException(); }
	protected override string ConvertPathToInternalImpl( UPath path ) { return path.FullName; }
	protected override UPath ConvertPathFromInternalImpl( string path ) { return new UPath( path ); }
	protected override IFileSystemWatcher WatchImpl( UPath path ) { return null!; } // Custom watcher logic if needed
	protected override IEnumerable<FileSystemItem> EnumerateItemsImpl( UPath path, SearchOption searchOption, SearchPredicate? searchPredicate ) 
	{ 
		return Enumerable.Empty<FileSystemItem>(); 
	}
	protected override void CreateSymbolicLinkImpl( UPath path, UPath targetPath ) { throw new UnauthorizedAccessException(); }
	protected override bool TryResolveLinkTargetImpl( UPath path, out UPath target ) { target = UPath.Empty; return false; }

	// Timestamps - just return default or DateTime.Now
	protected override DateTime GetLastAccessTimeImpl( UPath path ) { return DateTime.Now; }
	protected override DateTime GetLastWriteTimeImpl( UPath path ) { return DateTime.Now; }
	protected override DateTime GetCreationTimeImpl( UPath path ) { return DateTime.Now; }
}
