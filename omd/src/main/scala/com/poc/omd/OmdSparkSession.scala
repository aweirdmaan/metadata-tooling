package com.poc.omd

import org.apache.spark.sql.SparkSession

object OmdSparkSession {

  def builder(jobName: String): SparkSession.Builder = {
    val jwt = sys.env.getOrElse("OMD_JWT", throw new RuntimeException("OMD_JWT env var not set"))
    SparkSession.builder()
      .config("spark.extraListeners", "io.openlineage.spark.agent.OpenLineageSparkListener")
      .config("spark.openmetadata.transport.type", "openmetadata")
      .config("spark.openmetadata.transport.hostPort", "http://localhost:8585/api")
      .config("spark.openmetadata.transport.jwtToken", jwt)
      .config("spark.openmetadata.transport.pipelineServiceName", "spark-poc")
      .config("spark.openmetadata.transport.pipelineName", jobName)
      .config("spark.openmetadata.transport.databaseServiceNames", "local-files")
  }
}
