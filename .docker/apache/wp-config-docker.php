<?php

// A helper function to lookup "env_FILE", "env", then fallback
if (! function_exists('getenv_docker')) {
    function getenv_docker($env, $default) {
        if ($fileEnv = getenv($env . '_FILE')) {
            return rtrim(file_get_contents($fileEnv), "\r\n");
        } else if (($val = getenv($env)) !== false) {
            return $val;
        } else {
            return $default;
        }
    }
}

// Sync .env with docker environment
$docker_env = fopen(dirname(__DIR__) . '/.env', 'r');
$bedrock_env = file_get_contents(dirname(__DIR__) . '/.env');

while(! feof($docker_env)) {
    $env_line = fgets($docker_env);
    $env_segments = preg_split('/=/', $env_line);

    if(sizeof($env_segments) >= 2) {
        $env_name = trim($env_segments[0]);
        $env_value = trim(str_replace(['\'', '"'], '', $env_segments[1]));

        if(preg_match('/^#/', $env_name)) {
            $env_name_uncomment = trim(preg_replace('/^#\s+/', '', $env_name));
            $env_name = getenv($env_name_uncomment) ? $env_name_uncomment : $env_name;
        }

        $env_value = getenv_docker($env_name, $env_value);
        $bedrock_env = str_replace($env_line, "{$env_name}=\"{$env_value}\"\n", $bedrock_env);
    }
}

fclose($docker_env);
file_put_contents(dirname(__DIR__) . '/.env', $bedrock_env);
