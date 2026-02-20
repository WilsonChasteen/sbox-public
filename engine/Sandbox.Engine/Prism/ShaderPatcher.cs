using Sandbox;
using System;
using System.IO;
using System.Reflection;
using System.Text;

namespace Sandbox.Prism;

internal static class ShaderPatcher
{
	private static string _headerContent;

	public static Stream Patch( Stream sourceStream )
	{
		using var reader = new StreamReader( sourceStream, Encoding.UTF8, true, 4096, true );
		var content = reader.ReadToEnd();

		if ( _headerContent == null )
			LoadHeader();

		// Basic injection strategy:
		// Insert header at the beginning, or after specific defines?
		// S&box shaders often start with HEADER
		// We'll append our header to the COMMON block if it exists, or just at the top.
		
		var patched = content;
        
        // Check if we should inject
        // For now, inject at the top
        if ( !string.IsNullOrEmpty( _headerContent ) )
        {
             // If we have a COMMON block, inject inside it?
             // Or just #include logic?
             // Since we are creating a virtual file, we can't easily #include "prism/header.hlsl" unless the compiler can find it.
             // But we are the filesystem! If the compiler asks for "prism/header.hlsl", we should serve it.
             // For now, we inline the header content to be safe.
             
             patched = _headerContent + "\n" + content;
        }

		return new MemoryStream( Encoding.UTF8.GetBytes( patched ) );
	}

	private static void LoadHeader()
	{
		try
		{
			var assembly = typeof(ShaderPatcher).Assembly;
            // Resource name format: AssemblyName.Folder.Folder.FileName
            // engine/Sandbox.Engine/Prism/Shaders/header.hlsl
            // EmbeddedResource was "Prism/Shaders/**/*.hlsl"
            // The name should be "Sandbox.Engine.Prism.Shaders.header.hlsl" (depending on default namespace and folder)
            // Or just "Prism.Shaders.header.hlsl" if root namespace is Sandbox.Engine?
            
            // Let's try to find it
            var names = assembly.GetManifestResourceNames();
            var resourceName = names.FirstOrDefault( x => x.EndsWith( "header.hlsl" ) );
            
            if ( !string.IsNullOrEmpty( resourceName ) )
            {
			    using var stream = assembly.GetManifestResourceStream( resourceName );
			    using var reader = new StreamReader( stream );
			    _headerContent = reader.ReadToEnd();
            }
            else
            {
                Log.Warning( "Prism: Could not find embedded header.hlsl" );
                _headerContent = "// Prism Header Missing";
            }
		}
		catch ( Exception e )
		{
			Log.Error( e, "Prism: Failed to load header.hlsl" );
            _headerContent = "// Prism Header Error";
		}
	}
}
