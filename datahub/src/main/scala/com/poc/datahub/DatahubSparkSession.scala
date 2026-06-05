package com.poc.datahub

import org.apache.spark.sql.SparkSession

/** Builds a SparkSession wired with the DataHub Spark Lineage listener.
  *
  * The listener picks up Spark logical plans, derives lineage edges between
  * the read sources and write sinks, and posts MetadataChangeProposal events
  * to the DataHub GMS endpoint (default: http://localhost:8080).
  *
  * Dataset URNs land under platform=file, instance=<DATAHUB_PLATFORM_INSTANCE>
  * (defaults to "spark_poc"), so file paths like /tmp/sensor_profiles.parquet
  * become urn:li:dataset:(urn:li:dataPlatform:file,spark_poc.tmp.sensor_profiles,PROD).
  */
object DatahubSparkSession {

  def builder(jobName: String): SparkSession.Builder = {
    val gms = sys.env.getOrElse("DATAHUB_GMS", "http://localhost:8080")
    val token = sys.env.getOrElse("DATAHUB_TOKEN", "")
    val instance = sys.env.getOrElse("DATAHUB_PLATFORM_INSTANCE", "spark_poc")
    val base = SparkSession.builder()
      .config("spark.extraListeners", "datahub.spark.DatahubSparkListener")
      .config("spark.datahub.rest.server", gms)
      .config("spark.datahub.metadata.pipeline.platformInstance", instance)
      .config("spark.datahub.metadata.dataset.platformInstance", instance)
      .config("spark.datahub.metadata.dataset.env", "PROD")
      .config("spark.app.name", jobName)
    if (token.nonEmpty) base.config("spark.datahub.rest.token", token) else base
  }
}
